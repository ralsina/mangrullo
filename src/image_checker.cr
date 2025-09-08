require "http"
require "json"
require "./types"
require "./docker_client"

module Mangrullo
  class ImageChecker
    @docker_client : DockerClient
    @registry_client : HTTP::Client
    @auth_cache = Hash(String, NamedTuple(token: String, expires_at: Time)).new

    def initialize(@docker_client : DockerClient)
      @registry_client = HTTP::Client.new("registry-1.docker.io", 443, tls: true)
    end

    def needs_update?(container : ContainerInfo, allow_major_upgrade : Bool = false) : Bool
      # If using 'latest' tag, use simple digest comparison
      if container.image.includes?("latest")
        return image_has_update?(container.image)
      end

      # For versioned tags, find available updates based on version
      current_version = extract_version_from_image(container.image)
      return false unless current_version

      target_version = find_target_update_version(container.image, current_version, allow_major_upgrade)
      target_version != nil
    end

    private def parse_registry_info(image_name : String) : NamedTuple(registry_host: String, repository_path: String)
      # Parse the image name to extract registry and repository
      base_name = image_name.split(":").first

      # Handle different registry formats
      registry_host = "registry-1.docker.io" # Default to Docker Hub
      repository_path = base_name

      if base_name.includes?("/")
        parts = base_name.split("/")
        if parts[0].includes?(".") || parts[0].includes?(":")
          # This looks like a registry host (e.g., ghcr.io, registry.example.com:5000)
          registry_host = parts[0]
          repository_path = parts[1..-1].join("/")

          # Handle special registry mappings
          if registry_host == "lscr.io"
            # lscr.io is a vanity URL that redirects to ghcr.io
            # Images are actually hosted at ghcr.io/linuxserver
            registry_host = "ghcr.io"
            repository_path = "linuxserver/#{repository_path}"
          end
        else
          # This is a Docker Hub namespace/image (e.g., library/nginx)
          registry_host = "registry-1.docker.io"
          repository_path = base_name
        end
      else
        # Simple image name, assume Docker Hub library
        registry_host = "registry-1.docker.io"
        repository_path = "library/#{base_name}"
      end

      {registry_host: registry_host, repository_path: repository_path}
    end

    def extract_version_from_image(image_name : String) : Version?
      # Skip SHA256 digests (they are image IDs, not versioned images)
      return nil if image_name.starts_with?("sha256:")

      # Extract tag from image name (format: name:tag or name)
      parts = image_name.split(":")
      tag = parts.size > 1 ? parts.last : "latest"

      Version.parse(tag)
    end

    def find_target_update_version(image_name : String, current_version : Version, allow_major_upgrade : Bool) : Version?
      # Get all available versions from the registry
      all_versions = get_all_versions(image_name)
      return nil if all_versions.empty?

      # Filter versions that are newer than current version
      newer_versions = all_versions.select { |v| v > current_version }

      # Filter by major upgrade preference
      if allow_major_upgrade
        # Allow any newer version
        target_version = newer_versions.max?
      else
        # Only allow minor/patch updates within the same major version
        same_major_versions = newer_versions.select { |v| v.major == current_version.major }
        target_version = same_major_versions.max?
      end

      target_version
    end

    def get_all_versions(image_name : String) : Array(Version)
      registry_info = parse_registry_info(image_name)
      registry_host = registry_info[:registry_host]
      repository_path = registry_info[:repository_path]

      begin
        response = fetch_registry_tags(registry_host, repository_path)
        return [] of Version unless response && response.status_code == 200

        parse_versions_from_response(response)
      rescue ex : Socket::Error | IO::Error
        Log.error { "Network error getting all versions for #{image_name} from #{registry_host}: #{ex.message}" }
        [] of Version
      rescue ex : JSON::ParseException
        Log.error { "JSON parsing error getting all versions for #{image_name} from #{registry_host}: #{ex.message}" }
        [] of Version
      rescue ex
        Log.error { "Unexpected error getting all versions for #{image_name} from #{registry_host}: #{ex.message}" }
        [] of Version
      end
    end

    private def fetch_registry_tags(registry_host : String, repository_path : String) : HTTP::Client::Response?
      # Try authenticated client first
      auth_client = create_authenticated_client(registry_host, repository_path)

      if auth_client
        Log.debug { "Using authenticated client for #{registry_host}" }
        response = auth_client.get("/v2/#{repository_path}/tags/list")
      else
        # Fall back to unauthenticated client for registries that don't require auth
        Log.debug { "Using unauthenticated client for #{registry_host}" }
        registry_client = create_registry_client(registry_host)
        response = registry_client.get("/v2/#{repository_path}/tags/list")
      end

      response
    rescue ex : Socket::Error | IO::Error
      Log.error { "Network error fetching tags from #{registry_host}: #{ex.message}" }
      nil
    rescue ex
      Log.error { "Unexpected error fetching tags from #{registry_host}: #{ex.message}" }
      nil
    end

    private def parse_versions_from_response(response : HTTP::Client::Response) : Array(Version)
      json = JSON.parse(response.body)
      tags = json["tags"].as_a.map(&.as_s)

      # Filter and parse version tags
      versions = tags.compact_map { |tag| Version.parse(tag) }
      versions.sort!
    rescue ex : JSON::ParseException
      Log.error { "JSON parsing error parsing versions from response: #{ex.message}" }
      [] of Version
    rescue ex
      Log.error { "Unexpected error parsing versions from response: #{ex.message}" }
      [] of Version
    end

    def get_latest_version(image_name : String) : Version?
      # Skip SHA256 digests (they are image IDs, not versioned images)
      return nil if image_name.starts_with?("sha256:")

      registry_info = parse_registry_info(image_name)
      registry_host = registry_info[:registry_host]
      repository_path = registry_info[:repository_path]

      begin
        response = fetch_registry_tags(registry_host, repository_path)
        return nil unless response && response.status_code == 200

        versions = parse_versions_from_response(response)
        versions.last?
      rescue ex : Socket::Error | IO::Error
        Log.error { "Network error getting latest version for #{image_name} from #{registry_host}: #{ex.message}" }
        nil
      rescue ex : JSON::ParseException
        Log.error { "JSON parsing error getting latest version for #{image_name} from #{registry_host}: #{ex.message}" }
        nil
      rescue ex
        Log.error { "Unexpected error getting latest version for #{image_name} from #{registry_host}: #{ex.message}" }
        nil
      end
    end

    def get_remote_image_digest(image_name : String) : String?
      # Skip SHA256 digests (they are image IDs, not versioned images)
      return nil if image_name.starts_with?("sha256:")

      registry_info = parse_registry_info(image_name)
      registry_host = registry_info[:registry_host]
      repository_path = registry_info[:repository_path]

      tag = image_name.includes?(":") ? image_name.split(":").last : "latest"

      begin
        response = fetch_registry_digest(registry_host, repository_path, tag)
        return nil unless response && response.status_code == 200

        # The digest is in the Docker-Content-Digest header
        response.headers["Docker-Content-Digest"]?
      rescue ex : Socket::Error | IO::Error
        Log.error { "Network error getting remote digest for #{image_name} from #{registry_host}: #{ex.message}" }
        nil
      rescue ex
        Log.error { "Unexpected error getting remote digest for #{image_name} from #{registry_host}: #{ex.message}" }
        nil
      end
    end

    private def fetch_registry_digest(registry_host : String, repository_path : String, tag : String) : HTTP::Client::Response?
      headers = HTTP::Headers{
        "Accept" => "application/vnd.docker.distribution.manifest.v2+json",
      }

      # Try authenticated client first
      auth_client = create_authenticated_client(registry_host, repository_path)

      if auth_client
        Log.debug { "Using authenticated client for digest lookup on #{registry_host}" }
        response = auth_client.get("/v2/#{repository_path}/manifests/#{tag}", headers)
      else
        # Fall back to unauthenticated client
        Log.debug { "Using unauthenticated client for digest lookup on #{registry_host}" }
        registry_client = create_registry_client(registry_host)
        response = registry_client.get("/v2/#{repository_path}/manifests/#{tag}", headers)
      end

      response
    rescue ex : Socket::Error | IO::Error
      Log.error { "Network error fetching digest from #{registry_host}: #{ex.message}" }
      nil
    rescue ex
      Log.error { "Unexpected error fetching digest from #{registry_host}: #{ex.message}" }
      nil
    end

    def get_local_image_digest(image_name : String) : String?
      image_info = @docker_client.get_image_info(image_name)
      result = image_info.try(&.id)
      Log.debug { "get_local_image_digest: image_name=#{image_name}, result=#{result}" }
      result
    end

    def image_has_update?(image_name : String) : Bool
      local_digest = get_local_image_digest(image_name)
      return false unless local_digest

      remote_digest = get_remote_image_digest(image_name)
      return false unless remote_digest

      local_digest != remote_digest
    end

    def get_image_update_info(image_name : String) : NamedTuple(has_update: Bool, local_version: Version?, remote_version: Version?)
      # For 'latest' tags, use digest comparison
      if image_name.includes?("latest")
        has_update = image_has_update?(image_name)
        return {has_update: has_update, local_version: nil, remote_version: nil}
      end

      # For versioned tags, extract version and find target update
      local_version = extract_version_from_image(image_name)
      return {has_update: false, local_version: local_version, remote_version: nil} unless local_version

      # Find the target version we would update to
      target_version = find_target_update_version(image_name, local_version, true) # Use true to get latest available
      has_update = target_version != nil

      {has_update: has_update, local_version: local_version, remote_version: target_version}
    end

    def get_local_image_info(image_name : String) : NamedTuple(id: String?, digest: String?)
      begin
        # Get local image info through docker client
        image_info = @docker_client.get_image_info(image_name)
        if image_info
          {id: image_info.id, digest: nil} # Note: repo_digests not available in current implementation
        else
          {id: nil, digest: nil}
        end
      rescue ex : Docr::Errors::DockerAPIError
        Log.error { "Docker API error getting local image info for #{image_name}: #{ex.message}" }
        {id: nil, digest: nil}
      rescue ex : Socket::Error | IO::Error
        Log.error { "Network error getting local image info for #{image_name}: #{ex.message}" }
        {id: nil, digest: nil}
      rescue ex
        Log.error { "Unexpected error getting local image info for #{image_name}: #{ex.message}" }
        {id: nil, digest: nil}
      end
    end

    def get_container_image_digest(container_image_id : String) : String?
      # Extract the actual digest from container's image_id
      # Container image_id format is typically "sha256:digest" or just "digest"
      if container_image_id.starts_with?("sha256:")
        container_image_id
      else
        "sha256:#{container_image_id}"
      end
    end

    def get_remote_image_info(image_name : String) : NamedTuple(id: String?, digest: String?)
      begin
        # Try to get remote image info by creating it (this pulls latest info)
        # Note: This is a simplified approach - in practice we'd need a more sophisticated way
        # to get remote manifest without actually pulling
        {id: nil, digest: nil}
      rescue ex : Socket::Error | IO::Error
        Log.error { "Network error getting remote image info for #{image_name}: #{ex.message}" }
        {id: nil, digest: nil}
      rescue ex
        Log.error { "Unexpected error getting remote image info for #{image_name}: #{ex.message}" }
        {id: nil, digest: nil}
      end
    end

    private def map_registry_host(registry_host : String, repository_path : String) : NamedTuple(registry_host: String, repository_path: String)
      # Handle special registry mappings
      if registry_host == "lscr.io"
        # lscr.io is a vanity URL that redirects to ghcr.io
        # Images are actually hosted at ghcr.io/linuxserver
        {"ghcr.io", "linuxserver/#{repository_path}"}
      else
        {registry_host, repository_path}
      end
    end

    def create_registry_client(registry_host : String) : HTTP::Client
      if registry_host == "registry-1.docker.io"
        @registry_client # Reuse the existing Docker Hub client
      else
        # Create a new client for other registries
        HTTP::Client.new(registry_host, 443, tls: true)
      end
    end

    def get_remote_image_digest_for_registry(image_name : String, registry_host : String) : String?
      # Remove tag from image name
      base_name = image_name.split(":").first
      tag = image_name.includes?(":") ? image_name.split(":").last : "latest"

      # Handle repository path for non-Docker Hub registries
      repository_path = base_name
      if registry_host == "registry-1.docker.io" && !base_name.includes?("/")
        repository_path = "library/#{base_name}"
      end

      begin
        # Try authenticated client first
        auth_client = create_authenticated_client(registry_host, repository_path)

        headers = HTTP::Headers{
          "Accept" => "application/vnd.docker.distribution.manifest.v2+json",
        }

        if auth_client
          Log.debug { "get_remote_image_digest_for_registry: Using authenticated client for #{registry_host}" }
          response = auth_client.get("/v2/#{repository_path}/manifests/#{tag}", headers)
        else
          # Fall back to unauthenticated client
          Log.debug { "get_remote_image_digest_for_registry: Using unauthenticated client for #{registry_host}" }
          registry_client = create_registry_client(registry_host)
          response = registry_client.get("/v2/#{repository_path}/manifests/#{tag}", headers)
        end

        return nil unless response.status_code == 200

        # Extract digest from response headers
        response.headers["Docker-Content-Digest"]?
      rescue ex : Socket::Error | IO::Error
        Log.error { "Network error getting remote digest for #{image_name} from #{registry_host}: #{ex.message}" }
        nil
      rescue ex
        Log.error { "Unexpected error getting remote digest for #{image_name} from #{registry_host}: #{ex.message}" }
        nil
      end
    end

    # Authentication helper methods
    private def get_registry_token(registry_host : String, repository_path : String) : String?
      cache_key = "#{registry_host}:#{repository_path}"

      # Check cache first
      if cached = @auth_cache[cache_key]?
        return cached[:token] if cached[:expires_at] > Time.utc
      end

      begin
        token_url = case registry_host
                    when "registry-1.docker.io"
                      "https://auth.docker.io/token?service=registry.docker.io&scope=repository:#{repository_path}:pull"
                    when "ghcr.io"
                      "https://ghcr.io/token?scope=repository:#{repository_path}:pull"
                    else
                      # For other registries, try common patterns or return nil
                      Log.debug { "Unknown registry auth pattern for #{registry_host}" }
                      return nil
                    end

        Log.debug { "Getting token from: #{token_url}" }
        response = HTTP::Client.get(token_url)
        return nil unless response.status_code == 200

        json = JSON.parse(response.body)
        token = json["token"]?.try(&.as_s)
        return nil unless token

        # Cache the token (tokens typically expire in 5 minutes, be conservative)
        @auth_cache[cache_key] = {token: token, expires_at: Time.utc + 4.minutes}
        Log.debug { "Successfully cached token for #{cache_key}" }

        token
      rescue ex : Socket::Error | IO::Error
        Log.error { "Network error getting registry token for #{registry_host}: #{ex.message}" }
        nil
      rescue ex : JSON::ParseException
        Log.error { "JSON parsing error getting registry token for #{registry_host}: #{ex.message}" }
        nil
      rescue ex
        Log.error { "Unexpected error getting registry token for #{registry_host}: #{ex.message}" }
        nil
      end
    end

    private def create_authenticated_client(registry_host : String, repository_path : String) : HTTP::Client?
      token = get_registry_token(registry_host, repository_path)
      return nil unless token

      client = HTTP::Client.new(registry_host, 443, tls: true)
      client.before_request do |request|
        request.headers["Authorization"] = "Bearer #{token}"
      end
      client
    end
  end
end

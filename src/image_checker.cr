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
      # If using 'latest' tag, use the enhanced update status check
      if container.image.includes?("latest")
        status = get_update_status(container)
        return status[:needs_pull] || status[:needs_restart]
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
            # Don't double-prepend linuxserver if it's already there
            if repository_path.starts_with?("linuxserver/")
              repository_path = repository_path
            else
              repository_path = "linuxserver/#{repository_path}"
            end
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

      response = if auth_client
                   Log.debug { "Using authenticated client for #{registry_host}" }
                   auth_client.get("/v2/#{repository_path}/tags/list")
                 else
                   # Fall back to unauthenticated client for registries that don't require auth
                   Log.debug { "Using unauthenticated client for #{registry_host}" }
                   registry_client = create_registry_client(registry_host)
                   registry_client.get("/v2/#{repository_path}/tags/list")
                 end

      Log.debug { "Tags response for #{registry_host}/#{repository_path} - Status: #{response.status_code}" }

      if response.status_code != 200
        Log.error { "Registry returned status #{response.status_code} fetching tags for #{registry_host}/#{repository_path}" }
        Log.debug { "Response body: #{response.body}" }

        # For 404 errors, provide more helpful information
        if response.status_code == 404
          Log.error { "Image repository not found. This could mean:" }
          Log.error { "1. The repository doesn't exist in the registry" }
          Log.error { "2. The repository path is incorrect" }
          Log.error { "3. Authentication is required for this repository" }
          Log.error { "4. The repository name has been changed or moved" }
          Log.error { "   Expected repository path: #{repository_path}" }
          Log.error { "   Full URL: https://#{registry_host}/v2/#{repository_path}/tags/list" }
        end
        return nil
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

      Log.debug { "Getting remote digest for #{image_name} -> #{registry_host}/#{repository_path}:#{tag}" }

      begin
        response = fetch_registry_digest(registry_host, repository_path, tag)
        return nil unless response && response.status_code == 200

        # The digest is in the Docker-Content-Digest header
        digest = response.headers["Docker-Content-Digest"]?
        Log.debug { "Extracted remote digest for #{image_name}: #{digest}" }

        unless digest
          Log.error { "No Docker-Content-Digest header found for #{image_name}" }
          Log.debug { "Available headers: #{response.headers.keys}" }
        end

        digest
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
        "Accept"     => "application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.manifest.v1+json",
        "User-Agent" => "mangrullo/1.0",
      }

      # Try authenticated client first
      auth_client = create_authenticated_client(registry_host, repository_path)

      response = if auth_client
                   Log.debug { "Using authenticated client for digest lookup on #{registry_host}" }
                   auth_client.get("/v2/#{repository_path}/manifests/#{tag}", headers)
                 else
                   # Fall back to unauthenticated client
                   Log.debug { "Using unauthenticated client for digest lookup on #{registry_host}" }
                   registry_client = create_registry_client(registry_host)
                   registry_client.get("/v2/#{repository_path}/manifests/#{tag}", headers)
                 end

      Log.debug { "Registry response for #{registry_host}/#{repository_path}:#{tag} - Status: #{response.status_code}" }
      Log.debug { "Response headers: #{response.headers}" }
      Log.debug { "Content-Type: #{response.headers.fetch("Content-Type", nil)}" }

      if response.status_code != 200
        Log.error { "Registry returned status #{response.status_code} for #{registry_host}/#{repository_path}:#{tag}" }
        Log.debug { "Response body: #{response.body}" }

        # For 404 errors, provide more helpful information
        if response.status_code == 404
          Log.error { "Image not found in registry. This could mean:" }
          Log.error { "1. The image doesn't exist in the registry" }
          Log.error { "2. The repository path is incorrect" }
          Log.error { "3. Authentication is required for this image" }
          Log.error { "4. The image name has been changed or moved" }
        end
        return nil
      end

      digest_header = response.headers["Docker-Content-Digest"]?
      Log.debug { "Docker-Content-Digest header: #{digest_header}" }

      # If we got a manifest list, we need to parse it to find the manifest for our architecture
      content_type = response.headers["Content-Type"]?
      if content_type && content_type.includes?("manifest.list")
        Log.debug { "Got manifest list, need to find architecture-specific manifest" }
        Log.debug { "Manifest list body: #{response.body}" }
      end

      # Fallback: try to extract digest from manifest body if header is missing
      unless digest_header
        Log.debug { "No digest header found, trying to extract from manifest body" }
        digest_header = extract_digest_from_manifest(response.body)
        Log.debug { "Extracted digest from manifest: #{digest_header}" }
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
      Log.debug { "get_local_image_digest: image_name=#{image_name}" }

      # First try to get the repository digest from Docker CLI
      # This is what Docker uses for "up to date" comparisons
      begin
        output = IO::Memory.new
        error = IO::Memory.new
        status = Process.run("docker", ["image", "inspect", "--format={{index .RepoDigests 0}}", image_name],
          output: output, error: error)
        if status.success?
          repo_digest = output.to_s.strip
          if repo_digest.includes?("@sha256:")
            digest = repo_digest.split("@sha256:").last
            full_digest = "sha256:#{digest}"
            Log.debug { "get_local_image_digest: Got repo digest from docker inspect: #{full_digest}" }
            return full_digest
          end
        end
      rescue ex
        Log.debug { "get_local_image_digest: Docker inspect failed: #{ex.message}" }
      end

      # Fallback: Get the actual image info for the specified image name
      # This returns the image ID (manifest digest), which may not match remote digest for multi-arch images
      image_info = @docker_client.get_image_info(image_name)
      result = image_info.try(&.id)
      Log.debug { "get_local_image_digest: Falling back to image ID: #{result}" }
      result
    end

    def image_has_update?(image_name : String) : Bool
      local_digest = get_local_image_digest(image_name)
      return false unless local_digest

      remote_digest = get_remote_image_digest(image_name)
      return false unless remote_digest

      # Normalize digest formats for comparison
      normalized_local = normalize_digest(local_digest)
      normalized_remote = normalize_digest(remote_digest)

      Log.debug { "Digest comparison for #{image_name}:" }
      Log.debug { "  Original: local=#{local_digest}, remote=#{remote_digest}" }
      Log.debug { "  Normalized: local=#{normalized_local}, remote=#{normalized_remote}" }
      Log.debug { "  Digests equal? #{normalized_local == normalized_remote}" }

      normalized_local != normalized_remote
    end

    def get_update_status(container : ContainerInfo) : NamedTuple(needs_pull: Bool, needs_restart: Bool, local_digest: String?, remote_digest: String?)
      # Get the container's current image digest
      container_digest = container.image_id

      # Get the latest local image digest
      local_digest = get_local_image_digest(container.image)

      # Get the remote digest
      remote_digest = get_remote_image_digest(container.image)

      needs_pull = false
      needs_restart = false

      if local_digest && remote_digest
        normalized_local = normalize_digest(local_digest)
        normalized_remote = normalize_digest(remote_digest)
        normalized_container = normalize_digest(container_digest)

        needs_pull = normalized_local != normalized_remote
        needs_restart = normalized_container != normalized_local && !needs_pull

        Log.debug { "Update status for #{container.name}:" }
        Log.debug { "  Container digest: #{normalized_container}" }
        Log.debug { "  Local latest digest: #{normalized_local}" }
        Log.debug { "  Remote digest: #{normalized_remote}" }
        Log.debug { "  Needs pull: #{needs_pull}, Needs restart: #{needs_restart}" }
      end

      {
        needs_pull:    needs_pull,
        needs_restart: needs_restart,
        local_digest:  local_digest,
        remote_digest: remote_digest,
      }
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

    def get_container_image_digest(container_image_id : String) : String?
      # Extract the actual digest from container's image_id
      # Container image_id format is typically "sha256:digest" or just "digest"
      if container_image_id.starts_with?("sha256:")
        container_image_id
      else
        "sha256:#{container_image_id}"
      end
    end

    private def normalize_digest(digest : String) : String
      # Ensure digest has consistent sha256: prefix format
      if digest.starts_with?("sha256:")
        digest
      else
        "sha256:#{digest}"
      end
    end

    private def extract_digest_from_manifest(manifest_body : String) : String?
      begin
        json = JSON.parse(manifest_body)

        # Try different manifest formats
        if json["manifest"]? && json["manifest"].as_h?
          # Manifest list (multi-arch)
          manifest = json["manifest"].as_h
          manifest["digest"]?.try(&.as_s)
        elsif json["config"]? && json["config"].as_h?
          # Single manifest
          config = json["config"].as_h
          config["digest"]?.try(&.as_s)
        elsif json["layers"]? && json["layers"].as_a?
          # Another manifest format - look for digest in layers
          layers = json["layers"].as_a
          first_layer = layers.first?
          first_layer.try(&.as_h?).try(&.dig("digest")).try(&.as_s)
        else
          # Try to find any digest field in the JSON
          find_digest_in_json(json)
        end
      rescue ex : JSON::ParseException
        Log.debug { "Failed to parse manifest JSON: #{ex.message}" }
        nil
      rescue ex
        Log.debug { "Error extracting digest from manifest: #{ex.message}" }
        nil
      end
    end

    private def find_digest_in_json(json : JSON::Any) : String?
      # Recursively search for a digest field in the JSON
      if json.as_h?
        json.as_h.each do |key, value|
          if key == "digest" && value.as_s?
            return value.as_s
          elsif value.as_h? || value.as_a?
            result = find_digest_in_json(value)
            return result if result
          end
        end
      elsif json.as_a?
        json.as_a.each do |item|
          result = find_digest_in_json(item)
          return result if result
        end
      end
      nil
    end

    def get_remote_image_info(image_name : String) : NamedTuple(id: String?, digest: String?)
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
        Log.debug { "For repository: #{repository_path}" }
        response = HTTP::Client.get(token_url)
        Log.debug { "Token response status: #{response.status_code}" }
        Log.debug { "Token response body: #{response.body}" }
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

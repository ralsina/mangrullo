require "http"
require "json"
require "./types"
require "./docker_client"

module Mangrullo
  class ImageChecker
    @docker_client : DockerClient
    @registry_client : HTTP::Client

    def initialize(@docker_client : DockerClient)
      @registry_client = HTTP::Client.new("registry-1.docker.io", 443, tls: true)
    end

    def needs_update?(container : ContainerInfo, allow_major_upgrade : Bool = false) : Bool
      # If using 'latest' tag, always check for updates
      return true if container.image.includes?("latest")

      current_version = extract_version_from_image(container.image)
      return false unless current_version

      remote_version = get_latest_version(container.image)
      return false unless remote_version

      # Check if update is needed based on version
      if allow_major_upgrade
        remote_version > current_version
      else
        # Only update if not a major version upgrade
        remote_version > current_version && !current_version.major_upgrade?(remote_version)
      end
    end

    def extract_version_from_image(image_name : String) : Version?
      # Skip SHA256 digests (they are image IDs, not versioned images)
      return nil if image_name.starts_with?("sha256:")

      # Extract tag from image name (format: name:tag or name)
      parts = image_name.split(":")
      tag = parts.size > 1 ? parts.last : "latest"

      Version.parse(tag)
    end

    def get_latest_version(image_name : String) : Version?
      # Skip SHA256 digests (they are image IDs, not versioned images)
      return nil if image_name.starts_with?("sha256:")

      # Parse the image name to extract registry and repository
      base_name = image_name.split(":").first
      
      # Handle different registry formats
      registry_host = "registry-1.docker.io"  # Default to Docker Hub
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

      # Get image manifest from appropriate registry API
      begin
        registry_client = create_registry_client(registry_host)
        response = registry_client.get("/v2/#{repository_path}/tags/list")
        
        # Handle authentication errors gracefully
        if response.status_code == 401
          Log.debug { "Authentication required for #{registry_host}, skipping version lookup" }
          return nil
        end
        
        return nil unless response.status_code == 200

        json = JSON.parse(response.body)
        tags = json["tags"].as_a.map(&.as_s)

        # Filter out version tags and find the latest
        versions = tags.compact_map { |tag| Version.parse(tag) }.sort!
        versions.last?
      rescue ex
        Log.debug { "Failed to get latest version for #{image_name} from #{registry_host}: #{ex.message}" }
        nil
      end
    end

    def get_remote_image_digest(image_name : String) : String?
      # Skip SHA256 digests (they are image IDs, not versioned images)
      return nil if image_name.starts_with?("sha256:")

      # Parse the image name to extract registry and repository
      base_name = image_name.split(":").first
      
      # Handle different registry formats
      registry_host = "registry-1.docker.io"  # Default to Docker Hub
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

      tag = image_name.includes?(":") ? image_name.split(":").last : "latest"

      begin
        registry_client = create_registry_client(registry_host)
        
        # Get image manifest to get digest
        response = registry_client.get("/v2/#{repository_path}/manifests/#{tag}",
          HTTP::Headers{
            "Accept" => "application/vnd.docker.distribution.manifest.v2+json",
          })
        
        # Handle authentication errors gracefully
        if response.status_code == 401
          Log.debug { "Authentication required for #{registry_host}, skipping digest lookup" }
          return nil
        end

        return nil unless response.status_code == 200

        # The digest is in the Docker-Content-Digest header
        response.headers["Docker-Content-Digest"]?
      rescue ex
        Log.debug { "Failed to get remote digest for #{image_name} from #{registry_host}: #{ex.message}" }
        nil
      end
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
      # Try to get more accurate version info from digest tags first
      local_version = get_current_version_from_digest(image_name)
      
      # Fall back to extracting from image name if digest approach fails
      local_version ||= extract_version_from_image(image_name)
      
      remote_version = get_latest_version(image_name)

      has_update = if local_version && remote_version
                     remote_version > local_version
                   else
                     image_has_update?(image_name)
                   end

      {has_update: has_update, local_version: local_version, remote_version: remote_version}
    end

    def get_local_image_info(image_name : String) : NamedTuple(id: String?, digest: String?)
      begin
        # Get local image info through docker client
        image_info = @docker_client.get_image_info(image_name)
        if image_info
          {id: image_info.id, digest: nil}  # Note: repo_digests not available in current implementation
        else
          {id: nil, digest: nil}
        end
      rescue ex
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
      rescue ex
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

    def get_tags_for_digest(image_name : String, digest : String) : Array(String)
      Log.debug { "get_tags_for_digest: START image_name=#{image_name}, digest=#{digest}" }
      
      # Parse the image name to extract registry and repository
      base_name = image_name.split(":").first
      
      # Handle different registry formats
      registry_host = "registry-1.docker.io"  # Default to Docker Hub
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

      Log.debug { "get_tags_for_digest: image_name=#{image_name}, base_name=#{base_name}, registry_host=#{registry_host}, repository_path=#{repository_path}" }

      tags = [] of String

      begin
        # Create a registry client for this specific registry
        registry_client = create_registry_client(registry_host)
        
        # Get all tags for the image
        response = registry_client.get("/v2/#{repository_path}/tags/list")
        Log.debug { "get_tags_for_digest: registry response status: #{response.status_code}" }
        Log.debug { "get_tags_for_digest: registry response body: #{response.body}" }
        
        # Handle authentication errors gracefully
        if response.status_code == 401
          Log.debug { "get_tags_for_digest: Authentication required for #{registry_host}, skipping digest lookup" }
          return tags
        end
        
        return tags unless response.status_code == 200

        json = JSON.parse(response.body)
        all_tags = json["tags"].as_a.map(&.as_s)
        Log.debug { "get_tags_for_digest: found #{all_tags.size} total tags: #{all_tags[0..5].join(", ")}#{all_tags.size > 5 ? "..." : ""}" }

        # For each tag, check if it points to the same digest
        matching_tags = 0
        all_tags.each do |tag|
          begin
            tag_digest = get_remote_image_digest_for_registry("#{repository_path}:#{tag}", registry_host)
            Log.debug { "get_tags_for_digest: tag #{tag} has digest #{tag_digest}" }
            if tag_digest == digest
              tags << tag
              matching_tags += 1
              Log.debug { "get_tags_for_digest: MATCH! tag #{tag} matches digest #{digest}" }
            end
          rescue ex
            Log.debug { "get_tags_for_digest: failed to check tag #{tag}: #{ex.message}" }
            # Skip tags that can't be checked
            next
          end
        end

        Log.debug { "get_tags_for_digest: found #{matching_tags} matching tags out of #{all_tags.size} total" }
        Log.debug { "get_tags_for_digest: END returning tags: #{tags}" }
        tags
      rescue ex
        Log.debug { "get_tags_for_digest: FAILED with exception: #{ex.message}" }
        Log.debug { ex.backtrace.join("\n") } if ex.backtrace
        tags
      end
    end

    def create_registry_client(registry_host : String) : HTTP::Client
      if registry_host == "registry-1.docker.io"
        @registry_client  # Reuse the existing Docker Hub client
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
        registry_client = create_registry_client(registry_host)
        
        # Get image manifest to get digest
        response = registry_client.get("/v2/#{repository_path}/manifests/#{tag}",
          HTTP::Headers{
            "Accept" => "application/vnd.docker.distribution.manifest.v2+json",
          })
        
        # Handle authentication errors gracefully
        if response.status_code == 401
          Log.debug { "Authentication required for #{registry_host}, skipping digest lookup" }
          return nil
        end
        
        return nil unless response.status_code == 200

        # Extract digest from response headers
        response.headers["Docker-Content-Digest"]?
      rescue ex
        Log.debug { "Failed to get remote digest for #{image_name} from #{registry_host}: #{ex.message}" }
        nil
      end
    end

    def get_current_version_from_digest(image_name : String) : Version?
      # Get local image digest
      local_digest = get_local_image_digest(image_name)
      Log.debug { "get_current_version_from_digest: local_digest for #{image_name}: #{local_digest}" }
      return nil unless local_digest

      # Get all tags that point to this digest
      tags = get_tags_for_digest(image_name, local_digest)
      Log.debug { "get_current_version_from_digest: tags for digest #{local_digest}: #{tags}" }
      return nil if tags.empty?

      # Extract semantic versions from tags and find the highest one
      versions = tags.compact_map { |tag| 
        Log.debug { "Parsing version from tag: #{tag}" }
        Version.parse(tag) 
      }.sort!
      Log.debug { "get_current_version_from_digest: parsed versions: #{versions}" }
      versions.last?
    end
  end
end

require "./types"
require "./docker_client"
require "./image_checker"

module Mangrullo
  class UpdateManager
    @docker_client : DockerClient
    @image_checker : ImageChecker

    def initialize(@docker_client : DockerClient)
      @image_checker = ImageChecker.new(@docker_client)
    end

    def check_and_update_containers(allow_major_upgrade : Bool = false, container_names : Array(String) = [] of String) : Array(NamedTuple(container: ContainerInfo, updated: Bool, error: String?))
      results = [] of NamedTuple(container: ContainerInfo, updated: Bool, error: String?)

      Log.info { "Starting container update check" }

      begin
        containers = @docker_client.running_containers

        # Filter containers if specific names were provided
        unless container_names.empty?
          # Normalize container names for comparison (handle both "flatnotes" and "/flatnotes")
          normalized_input_names = container_names.map { |name| name.starts_with?("/") ? name : "/#{name}" }
          containers = containers.select { |container| 
            # Check both the actual container name and a version without leading slash
            normalized_input_names.includes?(container.name) || 
            normalized_input_names.includes?(container.name.lchop('/'))
          }
          Log.info { "Filtered to #{containers.size} containers matching: #{container_names.join(", ")}" }
        end

        Log.info { "Processing #{containers.size} containers" }

        containers.each do |container|
          Log.info { "Checking container: #{container.name} (#{container.image})" }

          result = update_container(container, allow_major_upgrade)
          results << result

          if result[:updated]
            Log.info { "Successfully updated container: #{container.name}" }
          elsif result[:error]
            Log.error { "Failed to update container #{container.name}: #{result[:error]}" }
          else
            Log.info { "Container #{container.name} is up to date" }
          end
        end

        Log.info { "Update check completed" }
      rescue ex : Docr::Errors::DockerAPIError
        Log.error { "Docker API error during container update check: #{ex.message}" }
        # Return empty results on critical failure
      rescue ex : Socket::Error | IO::Error
        Log.error { "Network error during container update check: #{ex.message}" }
        # Return empty results on critical failure
      rescue ex
        Log.error { "Unexpected error during container update check: #{ex.message}" }
        # Return empty results on critical failure
      end

      results
    end

    def update_container(container : ContainerInfo, allow_major_upgrade : Bool = false) : NamedTuple(container: ContainerInfo, updated: Bool, error: String?)
      # Check if update is needed
      unless @image_checker.needs_update?(container, allow_major_upgrade)
        return {container: container, updated: false, error: nil}
      end

      Log.info { "Update needed for container: #{container.name}" }

      # Debug: Show container state before update
      Log.debug { "Container state before update:" }
      Log.debug { "  Container image: #{container.image}" }
      Log.debug { "  Container image_id: #{container.image_id}" }
      
      # Get current digest information for debugging
      local_digest_before = @image_checker.get_local_image_digest(container.image)
      remote_digest_before = @image_checker.get_remote_image_digest(container.image)
      Log.debug { "  Local digest before: #{local_digest_before}" }
      Log.debug { "  Remote digest before: #{remote_digest_before}" }

      # Extract image name and tag
      image_parts = container.image.split(":")
      image_name = image_parts[0]
      image_tag = image_parts.size > 1 ? image_parts[1] : "latest"

      # Pull the new image
      Log.info { "Pulling new image: #{container.image}" }
      unless @docker_client.pull_image(image_name, image_tag)
        return {container: container, updated: false, error: "Failed to pull image"}
      end

      # Debug: Show state after pull
      Log.debug { "Container state after pull:" }
      local_digest_after_pull = @image_checker.get_local_image_digest(container.image)
      Log.debug { "  Local digest after pull: #{local_digest_after_pull}" }
      Log.debug { "  Remote digest: #{remote_digest_before}" }
      Log.debug { "  Digests match after pull? #{local_digest_after_pull == remote_digest_before}" }

      # Recreate the container with the new image (like watchtower does)
      Log.info { "Recreating container: #{container.name} with new image" }
      new_container_id = @docker_client.recreate_container_with_new_image(container.id, container.image)
      unless new_container_id
        return {container: container, updated: false, error: "Failed to recreate container with new image"}
      end

      Log.info { "Container successfully recreated with new image. New container ID: #{new_container_id}" }

      # Verify the recreation worked by checking the new container
      sleep 2.seconds # Give Docker a moment to fully start the new container
      updated_container = @docker_client.get_container_info(new_container_id)
      if updated_container
        Log.debug { "New container state after recreation:" }
        Log.debug { "  New container ID: #{updated_container.id}" }
        Log.debug { "  New container image_id: #{updated_container.image_id}" }
        Log.debug { "  Image ID changed from original? #{updated_container.image_id != container.image_id}" }
        
        # Verify the new container is actually using the new image
        local_digest_after = @image_checker.get_local_image_digest(container.image)
        remote_digest = @image_checker.get_remote_image_digest(container.image)
        if local_digest_after && remote_digest && local_digest_after == remote_digest
          Log.debug { "✅ Verification successful: new container is using the updated image" }
        else
          Log.warn { "⚠️  Verification warning: new container may not be using the latest image" }
          Log.debug { "  Local digest: #{local_digest_after}" }
          Log.debug { "  Remote digest: #{remote_digest}" }
        end
      else
        Log.warn { "Could not verify new container state - container may not be running" }
      end

      {container: container, updated: true, error: nil}
    rescue ex : Docr::Errors::DockerAPIError
      Log.error { "Docker API error updating container #{container.name}: #{ex.message}" }
      {container: container, updated: false, error: "Docker API error: #{ex.message}"}
    rescue ex : Socket::Error | IO::Error
      Log.error { "Network error updating container #{container.name}: #{ex.message}" }
      {container: container, updated: false, error: "Network error: #{ex.message}"}
    rescue ex
      Log.error { "Unexpected error updating container #{container.name}: #{ex.message}" }
      {container: container, updated: false, error: "Unexpected error: #{ex.message}"}
    end

    def get_containers_needing_update(allow_major_upgrade : Bool = false, container_names : Array(String) = [] of String) : Array(ContainerInfo)
      containers = @docker_client.running_containers

      # Filter containers if specific names were provided
      unless container_names.empty?
        # Normalize container names for comparison (handle both "flatnotes" and "/flatnotes")
        normalized_input_names = container_names.map { |name| name.starts_with?("/") ? name : "/#{name}" }
        containers = containers.select { |container| 
          # Check both the actual container name and a version without leading slash
          normalized_input_names.includes?(container.name) || 
          normalized_input_names.includes?(container.name.lchop('/'))
        }
      end

      containers.select { |container| @image_checker.needs_update?(container, allow_major_upgrade) }
    rescue ex : Docr::Errors::DockerAPIError
      Log.error { "Docker API error getting containers needing update: #{ex.message}" }
      [] of ContainerInfo
    rescue ex : Socket::Error | IO::Error
      Log.error { "Network error getting containers needing update: #{ex.message}" }
      [] of ContainerInfo
    rescue ex
      Log.error { "Unexpected error getting containers needing update: #{ex.message}" }
      [] of ContainerInfo
    end

    def get_update_summary(allow_major_upgrade : Bool = false, container_names : Array(String) = [] of String) : NamedTuple(total: Int32, needing_update: Int32, update_candidates: Array(ContainerInfo))
      containers = @docker_client.running_containers

      # Filter containers if specific names were provided
      unless container_names.empty?
        # Normalize container names for comparison (handle both "flatnotes" and "/flatnotes")
        normalized_input_names = container_names.map { |name| name.starts_with?("/") ? name : "/#{name}" }
        containers = containers.select { |container| 
          # Check both the actual container name and a version without leading slash
          normalized_input_names.includes?(container.name) || 
          normalized_input_names.includes?(container.name.lchop('/'))
        }
      end

      needing_update = get_containers_needing_update(allow_major_upgrade, container_names)

      {
        total:             containers.size,
        needing_update:    needing_update.size,
        update_candidates: needing_update,
      }
    rescue ex : Docr::Errors::DockerAPIError
      Log.error { "Docker API error getting update summary: #{ex.message}" }
      {total: 0, needing_update: 0, update_candidates: [] of ContainerInfo}
    rescue ex : Socket::Error | IO::Error
      Log.error { "Network error getting update summary: #{ex.message}" }
      {total: 0, needing_update: 0, update_candidates: [] of ContainerInfo}
    rescue ex
      Log.error { "Unexpected error getting update summary: #{ex.message}" }
      {total: 0, needing_update: 0, update_candidates: [] of ContainerInfo}
    end

    def dry_run(allow_major_upgrade : Bool = false, container_names : Array(String) = [] of String) : Array(NamedTuple(container: ContainerInfo, needs_update: Bool, reason: String?))
      containers = @docker_client.running_containers

      # Filter containers if specific names were provided
      if container_names.empty?
        Log.info { "Dry run: checking all #{containers.size} containers" }
      else
        # Normalize container names for comparison (handle both "flatnotes" and "/flatnotes")
        normalized_input_names = container_names.map { |name| name.starts_with?("/") ? name : "/#{name}" }
        containers = containers.select { |container| 
          # Check both the actual container name and a version without leading slash
          normalized_input_names.includes?(container.name) || 
          normalized_input_names.includes?(container.name.lchop('/'))
        }
        Log.info { "Dry run: filtered to #{containers.size} containers matching: #{container_names.join(", ")}" }
      end

      containers.map { |container| process_container_for_dry_run(container, allow_major_upgrade) }
    rescue ex : Docr::Errors::DockerAPIError
      Log.error { "Docker API error during dry run: #{ex.message}" }
      Log.error { ex.backtrace.join("\n") } if ex.backtrace
      [] of NamedTuple(container: ContainerInfo, needs_update: Bool, reason: String?)
    rescue ex : Socket::Error | IO::Error
      Log.error { "Network error during dry run: #{ex.message}" }
      Log.error { ex.backtrace.join("\n") } if ex.backtrace
      [] of NamedTuple(container: ContainerInfo, needs_update: Bool, reason: String?)
    rescue ex
      Log.error { "Unexpected error during dry run: #{ex.message}" }
      Log.error { ex.backtrace.join("\n") } if ex.backtrace
      [] of NamedTuple(container: ContainerInfo, needs_update: Bool, reason: String?)
    end

    private def process_container_for_dry_run(container : ContainerInfo, allow_major_upgrade : Bool) : NamedTuple(container: ContainerInfo, needs_update: Bool, reason: String?)
      Log.debug { "Processing container: #{container.name} (#{container.image})" }

      # For latest tags, use detailed status to provide better reasons
      if container.image.includes?("latest")
        status = @image_checker.get_update_status(container)
        needs_update = status[:needs_pull] || status[:needs_restart]
        reason = if status[:needs_pull]
                   "New image version available (requires pull)"
                 elsif status[:needs_restart]
                   "Container restart required to use latest local image"
                 else
                   nil
                 end
      else
        needs_update = @image_checker.needs_update?(container, allow_major_upgrade)
        reason = if needs_update
                   generate_update_reason(container)
                 else
                   nil
                 end
      end

      {container: container, needs_update: needs_update, reason: reason}
    rescue ex : Docr::Errors::DockerAPIError
      Log.error { "Docker API error processing container #{container.name}: #{ex.message}" }
      Log.debug { "Container details - ID: #{container.id}, Image: #{container.image}" }
      {container: container, needs_update: false, reason: "Docker API error processing container"}
    rescue ex : Socket::Error | IO::Error
      Log.error { "Network error processing container #{container.name}: #{ex.message}" }
      Log.debug { "Container details - ID: #{container.id}, Image: #{container.image}" }
      {container: container, needs_update: false, reason: "Network error processing container"}
    rescue ex
      Log.error { "Unexpected error processing container #{container.name}: #{ex.message}" }
      Log.debug { "Container details - ID: #{container.id}, Image: #{container.image}" }
      {container: container, needs_update: false, reason: "Unexpected error processing container"}
    end

    private def generate_update_reason(container : ContainerInfo) : String
      Log.debug { "Checking update info for: #{container.image}" }
      update_info = @image_checker.get_image_update_info(container.image)

      Log.debug { "Update info: local_version=#{update_info[:local_version].inspect}, remote_version=#{update_info[:remote_version].inspect}" }

      if update_info[:local_version] && update_info[:remote_version]
        local_str = update_info[:local_version].to_s
        remote_str = update_info[:remote_version].to_s
        Log.debug { "Version strings: local='#{local_str}', remote='#{remote_str}'" }
        "Version update available: #{local_str} -> #{remote_str}"
      else
        generate_fallback_update_message(container, update_info)
      end
    rescue ex : Socket::Error | IO::Error
      Log.error { "Network error generating update reason for #{container.image}: #{ex.message}" }
      "Update available for #{container.image} (network error)"
    rescue ex : JSON::ParseException
      Log.error { "JSON parsing error generating update reason for #{container.image}: #{ex.message}" }
      "Update available for #{container.image} (parsing error)"
    rescue ex
      Log.error { "Unexpected error generating update reason for #{container.image}: #{ex.message}" }
      "Update available for #{container.image}"
    end

    private def generate_fallback_update_message(container : ContainerInfo, update_info) : String
      # Get local image info for better messaging
      local_info = {id: container.image_id, digest: @image_checker.get_container_image_digest(container.image_id)}

      if update_info[:local_version]
        "Update available for #{container.image} (current: #{update_info[:local_version]})"
      elsif local_info[:digest]
        # For digest-based images, try to extract version from image tag
        simple_version = @image_checker.extract_version_from_image(container.image)
        Log.debug { "Simple version extraction for #{container.image}: #{simple_version}" }

        if simple_version
          "Update available for #{container.image} (current: #{simple_version})"
        else
          # Extract the tag directly for non-semantic versions like "latest"
          tag = container.image.includes?(":") ? container.image.split(":").last : "latest"
          "Update available for #{container.image} (current: #{tag})"
        end
      elsif image_id = local_info[:id]
        "Update available for #{container.image} (image ID: #{image_id[0..11]}...)"
      else
        "Update available for #{container.image}"
      end
    rescue ex : Socket::Error | IO::Error
      Log.error { "Network error generating fallback update message for #{container.image}: #{ex.message}" }
      "Update available for #{container.image} (network error)"
    rescue ex
      Log.error { "Unexpected error generating fallback update message for #{container.image}: #{ex.message}" }
      "Update available for #{container.image}"
    end
  end
end

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

    def check_and_update_containers(allow_major_upgrade : Bool = false) : Array(NamedTuple(container: ContainerInfo, updated: Bool, error: String?))
      results = [] of NamedTuple(container: ContainerInfo, updated: Bool, error: String?)

      Log.info { "Starting container update check" }

      containers = @docker_client.running_containers
      Log.info { "Found #{containers.size} running containers" }

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
      results
    end

    def update_container(container : ContainerInfo, allow_major_upgrade : Bool = false) : NamedTuple(container: ContainerInfo, updated: Bool, error: String?)
      # Check if update is needed
      unless @image_checker.needs_update?(container, allow_major_upgrade)
        return {container: container, updated: false, error: nil}
      end

      Log.info { "Update needed for container: #{container.name}" }

      # Extract image name and tag
      image_parts = container.image.split(":")
      image_name = image_parts[0]
      image_tag = image_parts.size > 1 ? image_parts[1] : "latest"

      # Pull the new image
      Log.info { "Pulling new image: #{container.image}" }
      unless @docker_client.pull_image(image_name, image_tag)
        return {container: container, updated: false, error: "Failed to pull image"}
      end

      # Restart the container
      Log.info { "Restarting container: #{container.name}" }
      unless @docker_client.restart_container(container.id)
        return {container: container, updated: false, error: "Failed to restart container"}
      end

      {container: container, updated: true, error: nil}
    rescue ex : Exception
      {container: container, updated: false, error: ex.message}
    end

    def get_containers_needing_update(allow_major_upgrade : Bool = false) : Array(ContainerInfo)
      containers = @docker_client.running_containers
      containers.select { |container| @image_checker.needs_update?(container, allow_major_upgrade) }
    end

    def get_update_summary(allow_major_upgrade : Bool = false) : NamedTuple(total: Int32, needing_update: Int32, update_candidates: Array(ContainerInfo))
      containers = @docker_client.running_containers
      needing_update = get_containers_needing_update(allow_major_upgrade)

      {
        total:             containers.size,
        needing_update:    needing_update.size,
        update_candidates: needing_update,
      }
    end

    def dry_run(allow_major_upgrade : Bool = false) : Array(NamedTuple(container: ContainerInfo, needs_update: Bool, reason: String?))
      results = [] of NamedTuple(container: ContainerInfo, needs_update: Bool, reason: String?)

      begin
        containers = @docker_client.running_containers
        Log.info { "Dry run: checking #{containers.size} containers" }

        containers.each do |container|
          begin
            Log.debug { "Processing container: #{container.name} (#{container.image})" }
            needs_update = @image_checker.needs_update?(container, allow_major_upgrade)
            reason = if needs_update
                       begin
                         Log.debug { "Checking update info for: #{container.image}" }
                         update_info = @image_checker.get_image_update_info(container.image)
                         if update_info[:local_version] && update_info[:remote_version]
                           "Version update available: #{update_info[:local_version]} -> #{update_info[:remote_version]}"
                         else
                           # Get local image info for better messaging
                           local_info = {id: container.image_id, digest: @image_checker.get_container_image_digest(container.image_id)}
                           
                           # Try to get more specific version information
                           if update_info[:local_version] && update_info[:remote_version]
                             "Version update available: #{update_info[:local_version]} -> #{update_info[:remote_version]}"
                           elsif update_info[:local_version]
                             "Update available for #{container.image} (current: #{update_info[:local_version]})"
                           elsif local_info[:digest]
                             # Try to get at least some version info from the digest-based approach
                             digest_version = @image_checker.get_current_version_from_digest(container.image)
                             Log.debug { "Digest version lookup for #{container.image}: #{digest_version}" }
                             if digest_version
                               "Update available for #{container.image} (current: #{digest_version})"
                             else
                               # Fall back to simple version extraction from image tag
                               simple_version = @image_checker.extract_version_from_image(container.image)
                               Log.debug { "Simple version extraction for #{container.image}: #{simple_version}" }
                               if simple_version
                                 "Update available for #{container.image} (current: #{simple_version})"
                               else
                                 # Extract the tag directly for non-semantic versions like "latest"
                                 if container.image.includes?(":")
                                   tag = container.image.split(":").last
                                   "Update available for #{container.image} (current: #{tag})"
                                 else
                                   "Update available for #{container.image} (current: latest)"
                                 end
                               end
                             end
                           elsif (image_id = local_info[:id])
                             "Update available for #{container.image} (image ID: #{image_id[0..11]}...)"
                           else
                             "Update available for #{container.image}"
                           end
                         end
                       rescue ex
                         "Update available for #{container.image}"
                       end
                     else
                       nil
                     end

            results << {container: container, needs_update: needs_update, reason: reason}
          rescue ex
            Log.error { "Error processing container #{container.name}: #{ex.message}" }
            Log.debug { "Container details - ID: #{container.id}, Image: #{container.image}" }
            results << {container: container, needs_update: false, reason: "Error processing container"}
          end
        end
      rescue ex
        Log.error { "Error during dry run: #{ex.message}" }
        Log.error { ex.backtrace.join("\n") } if ex.backtrace
      end

      results
    end
  end
end

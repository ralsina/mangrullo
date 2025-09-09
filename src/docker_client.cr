require "docr"
require "./types"
require "./error_handling"

module Mangrullo
  # Custom Docker client that supports configurable socket paths
  class CustomDockerClient < Docr::Client
    def initialize(socket_path : String = "/var/run/docker.sock")
      socket = UNIXSocket.new(socket_path)
      @client = HTTP::Client.new(socket)
    end
  end

  class DockerClient
    @api : Docr::API

    def initialize(socket_path : String = "/var/run/docker.sock")
      client = CustomDockerClient.new(socket_path)
      @api = Docr::API.new(client)
    end

    def list_containers(all : Bool = false, filters : Hash(String, Array(String)) = {} of String => Array(String)) : Array(ContainerInfo)
      containers = @api.containers.list(all: all)

      containers.map do |container|
        # Defensive handling of container names
        container_name = if container.names && !container.names.empty?
                           container.names.first
                         else
                           # Fallback to first 12 chars of container ID, or full ID if shorter
                           container_id = container.id
                           if container_id.size > 12
                             container_id[0..12]
                           else
                             container_id
                           end
                         end

        ContainerInfo.new(
          id: container.id,
          name: container_name,
          image: container.image,
          image_id: container.image_id,
          labels: container.labels || {} of String => String,
          status: container.status || "unknown",
          created: Time.unix(container.created)
        )
      end
    end

    def get_container_info(container_id : String) : ContainerInfo?
      containers = @api.containers.list(all: true, filters: {"id" => [container_id]})
      return nil if containers.empty?

      container = containers.first

      # Defensive handling of container names
      container_name = if container.names && !container.names.empty?
                         container.names.first
                       else
                         # Fallback to first 12 chars of container ID, or full ID if shorter
                         container_id = container.id
                         if container_id.size > 12
                           container_id[0..12]
                         else
                           container_id
                         end
                       end

      ContainerInfo.new(
        id: container.id,
        name: container_name,
        image: container.image,
        image_id: container.image_id,
        labels: container.labels || {} of String => String,
        status: container.status || "unknown",
        created: Time.unix(container.created)
      )
    rescue ex : Docr::Errors::DockerAPIError
      Log.error { "Docker API error getting container info: #{ex.message}" }
      nil
    rescue ex : Socket::Error | IO::Error
      Log.error { "Network error getting container info: #{ex.message}" }
      nil
    rescue ex
      Log.error { "Unexpected error getting container info: #{ex.message}" }
      nil
    end

    def get_image_info(image_name : String) : ImageInfo?
      Log.debug { "get_image_info: Looking for image #{image_name}" }
      images = @api.images.list(filters: {"reference" => [image_name]})
      Log.debug { "get_image_info: Found #{images.size} images for #{image_name}" }
      return nil if images.empty?

      # Find the image that actually has the matching repo tag
      # The Docker API reference filter is not reliable, so we need to manually verify
      correct_image = images.find do |img|
        (img.repo_tags || [] of String).includes?(image_name)
      end

      unless correct_image
        Log.debug { "get_image_info: No image found with exact tag match for #{image_name}" }
        Log.debug { "get_image_info: Available tags from first few images:" }
        images.first(3).each_with_index do |img, i|
          Log.debug { "get_image_info: Image #{i + 1}: tags=#{img.repo_tags}" }
        end
        return nil
      end

      Log.debug { "get_image_info: Found correct image ID=#{correct_image.id}, repo_tags=#{correct_image.repo_tags}" }

      result = ImageInfo.new(
        id: correct_image.id,
        repo_tags: correct_image.repo_tags || [] of String,
        created: Time.unix(correct_image.created),
        size: correct_image.size.to_u64,
        labels: correct_image.labels || {} of String => String
      )
      Log.debug { "get_image_info: Returning ImageInfo with id=#{result.id}" }
      result
    rescue ex : Docr::Errors::DockerAPIError
      Log.error { "Docker API error getting image info: #{ex.message}" }
      nil
    rescue ex : Socket::Error | IO::Error
      Log.error { "Network error getting image info: #{ex.message}" }
      nil
    rescue ex
      Log.error { "Unexpected error getting image info: #{ex.message}" }
      nil
    end

    def inspect_image(image_name : String) : String?
      begin
        image_inspect = @api.images.inspect(image_name)
        repo_digest = image_inspect.repo_digests.first?
        return repo_digest if repo_digest
      rescue ex : Docr::Errors::DockerAPIError
        Log.debug { "docr error inspecting image #{image_name}: #{ex.message}" }
      end
      nil
    end

    def pull_image(image_name : String, tag : String = "latest") : Bool
      @api.images.create("#{image_name}:#{tag}")
      true
    rescue ex : Docr::Errors::DockerAPIError
      Log.error { "Docker API error pulling image: #{ex.message}" }
      false
    rescue ex : Socket::Error | IO::Error
      Log.error { "Network error pulling image: #{ex.message}" }
      false
    rescue ex
      Log.error { "Unexpected error pulling image: #{ex.message}" }
      false
    end

    def restart_container(container_id : String) : Bool
      @api.containers.restart(container_id)
      true
    rescue ex : Docr::Errors::DockerAPIError
      Log.error { "Docker API error restarting container: #{ex.message}" }
      false
    rescue ex : Socket::Error | IO::Error
      Log.error { "Network error restarting container: #{ex.message}" }
      false
    rescue ex
      Log.error { "Unexpected error restarting container: #{ex.message}" }
      false
    end

    def stop_container(container_id : String) : Bool
      @api.containers.stop(container_id)
      true
    rescue ex : Docr::Errors::DockerAPIError
      Log.error { "Docker API error stopping container: #{ex.message}" }
      false
    rescue ex : Socket::Error | IO::Error
      Log.error { "Network error stopping container: #{ex.message}" }
      false
    rescue ex
      Log.error { "Unexpected error stopping container: #{ex.message}" }
      false
    end

    def remove_container(container_id : String) : Bool
      @api.containers.delete(container_id)
      true
    rescue ex : Docr::Errors::DockerAPIError
      Log.error { "Docker API error removing container: #{ex.message}" }
      false
    rescue ex : Socket::Error | IO::Error
      Log.error { "Network error removing container: #{ex.message}" }
      false
    rescue ex
      Log.error { "Unexpected error removing container: #{ex.message}" }
      false
    end

    def stop_and_remove_container(container_id : String) : Bool
      # Stop the container first
      unless stop_container(container_id)
        return false
      end

      # Remove the container
      remove_container(container_id)
    end

    def create_container_from_inspect_data(image_name : String, container_name : String, inspect_data : String) : String?
      # Create a new container using the captured inspect data and new image
      begin
        Log.debug { "Creating container #{container_name} from inspect data with image #{image_name}" }
        
        # Parse the container inspection output
        container_info = JSON.parse(inspect_data).as_a.first?
        return nil unless container_info
        
        # Extract the container configuration
        config_data = container_info.as_h
        host_config_json = config_data["HostConfig"]?.try(&.as_h)
        config_json = config_data["Config"]?.try(&.as_h)

        return nil unless config_json

        # Build the container config
        container_config = Docr::Types::CreateContainerConfig.from_json(config_json.to_json)
        container_config.image = image_name

        if host_config_json
          host_config = Docr::Types::HostConfig.from_json(host_config_json.to_json)
          container_config.host_config = host_config
        end

        # Create the container
        response = @api.containers.create(container_name, container_config)
        response.id
      rescue ex : Docr::Errors::DockerAPIError
        Log.error { "Error creating container from inspect data: #{ex.message}" }
        nil
      rescue ex : JSON::ParseException
        Log.error { "Error parsing inspect data: #{ex.message}" }
        nil
      rescue ex
        Log.error { "Unexpected error creating container from inspect data: #{ex.message}" }
        nil
      end
    end

    def create_container_with_config(image_name : String, container_name : String, config : Hash(String, JSON::Any)) : String?
      # Get the original container's configuration using docker inspect
      begin
        inspect_data = inspect_container(container_name)

        unless inspect_data
          Log.error { "Failed to inspect container #{container_name} for configuration" }
          return nil
        end
        
        # Parse the container inspection output
        container_info = JSON.parse(inspect_data).as_a.first?
        return nil unless container_info
        
        # Extract the container configuration
        config_data = container_info.as_h
        host_config_json = config_data["HostConfig"]?.try(&.as_h)
        config_json = config_data["Config"]?.try(&.as_h)

        return nil unless config_json

        # Build the container config
        container_config = Docr::Types::CreateContainerConfig.from_json(config_json.to_json)
        container_config.image = image_name

        if host_config_json
          host_config = Docr::Types::HostConfig.from_json(host_config_json.to_json)
          container_config.host_config = host_config
        end

        # Create the container
        response = @api.containers.create(container_name, container_config)
        response.id
      rescue ex : Docr::Errors::DockerAPIError
        Log.error { "Error creating container with config: #{ex.message}" }
        nil
      rescue ex : JSON::ParseException
        Log.error { "Error parsing inspect data: #{ex.message}" }
        nil
      rescue ex
        Log.error { "Unexpected error creating container with config: #{ex.message}" }
        nil
      end
    end

    def start_container(container_id : String) : Bool
      begin
        @api.containers.start(container_id)
        true
      rescue ex : Docr::Errors::DockerAPIError
        Log.error { "Docker API error starting container: #{ex.message}" }
        false
      rescue ex : Socket::Error | IO::Error
        Log.error { "Network error starting container: #{ex.message}" }
        false
      rescue ex
        Log.error { "Unexpected error starting container: #{ex.message}" }
        false
      end
    end

    def recreate_container_with_new_image(container_id : String, new_image : String) : String?
      # Get container info first
      container_info = get_container_info(container_id)
      return nil unless container_info
      
      # Get the container name (remove leading slash)
      container_name = container_info.name.lchop('/')
      
      Log.info { "Recreating container #{container_name} with image #{new_image}" }
      
      # Capture container configuration BEFORE removing it
      Log.debug { "Capturing container configuration for #{container_name}" }
      
      # Get the container configuration using docker inspect BEFORE removing it
      config_output = inspect_container(container_name)

      unless config_output
        Log.error { "Failed to inspect container #{container_name} for configuration" }
        return nil
      end
      
      # Stop the container
      unless stop_container(container_id)
        Log.error { "Failed to stop container #{container_name}" }
        return nil
      end
      
      # Remove the old container FIRST to free up the name
      unless remove_container(container_id)
        Log.error { "Failed to remove old container #{container_name}" }
        return nil
      end
      
      # Create new container with the captured configuration and new image
      new_container_id = create_container_from_inspect_data(new_image, container_name, config_output.to_s)
      return nil unless new_container_id
      
      # Start the new container
      unless start_container(new_container_id)
        Log.error { "Failed to start new container #{container_name}" }
        return nil
      end
      
      Log.info { "Successfully recreated container #{container_name} with new image" }
      new_container_id
    end

    def get_container_logs(container_id : String, tail : Int32 = 100) : String
      @api.containers.logs(container_id, tail: tail.to_s).gets_to_end
    rescue ex : Docr::Errors::DockerAPIError
      Log.error { "Docker API error getting container logs: #{ex.message}" }
      ""
    rescue ex : Socket::Error | IO::Error
      Log.error { "Network error getting container logs: #{ex.message}" }
      ""
    rescue ex
      Log.error { "Unexpected error getting container logs: #{ex.message}" }
      ""
    end

    def inspect_container(container_id : String) : String?
      @api.containers.inspect(container_id).to_json
    rescue ex : Docr::Errors::DockerAPIError
      Log.error { "Docker API error inspecting container: #{ex.message}" }
      nil
    rescue ex : Socket::Error | IO::Error
      Log.error { "Network error inspecting container: #{ex.message}" }
      nil
    rescue ex
      Log.error { "Unexpected error inspecting container: #{ex.message}" }
      nil
    end

    def running_containers : Array(ContainerInfo)
      list_containers(all: false, filters: {"status" => ["running"]})
    end

    def container_exists?(container_id : String) : Bool
      !get_container_info(container_id).nil?
    end

    def image_exists?(image_name : String) : Bool
      !get_image_info(image_name).nil?
    end
  end
end

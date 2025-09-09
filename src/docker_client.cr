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
        host_config = config_data["HostConfig"]?.try(&.as_h)
        config = config_data["Config"]?.try(&.as_h)
        
        # Build docker create command with original configuration
        create_args = ["create", "--name", container_name]
        
        # Add environment variables
        if config && (env_vars = config["Env"]?.try(&.as_a))
          env_vars.each do |env_var|
            env_str = env_var.as_s
            create_args << "--env"
            create_args << env_str
          end
        end
        
        # Add port mappings
        if host_config && (port_bindings = host_config["PortBindings"]?.try(&.as_h))
          port_bindings.each do |container_port_key, host_bindings|
            container_port = container_port_key.to_s
            if host_bindings.as_a.size > 0
              host_binding = host_bindings.as_a.first.try(&.as_h)
              if host_binding
                host_ip = host_binding["HostIp"]?.try(&.as_s) || ""
                host_port = host_binding["HostPort"]?.try(&.as_s) || ""
                
                port_mapping = if host_ip && !host_ip.empty?
                             "#{host_ip}:#{host_port}:#{container_port}"
                           elsif host_port && !host_port.empty?
                             "#{host_port}:#{container_port}"
                           else
                             container_port
                           end
                
                create_args << "-p"
                create_args << port_mapping
              end
            end
          end
        end
        
        # Add volume mappings
        if host_config && (volume_binds = host_config["Binds"]?.try(&.as_a))
          volume_binds.each do |volume|
            volume_str = volume.as_s
            create_args << "-v"
            create_args << volume_str
          end
        end
        
        # Add network settings
        if config && (exposed_ports = config["ExposedPorts"]?.try(&.as_h))
          exposed_ports.keys.each do |port|
            port_str = port.to_s
            create_args << "--expose"
            create_args << port_str
          end
        end
        
        # Add restart policy
        if host_config && (restart_policy = host_config["RestartPolicy"]?.try(&.as_h))
          policy_name = restart_policy["Name"]?.try(&.as_s)
          if policy_name && policy_name != "no"
            create_args << "--restart"
            create_args << policy_name
          end
        end
        
        # Add the new image
        create_args << image_name
        
        Log.debug { "Docker create command: docker #{create_args.join(" ")}" }
        
        # Execute the docker create command
        output = IO::Memory.new
        error = IO::Memory.new
        status = Process.run("docker", create_args,
          output: output, error: error)
        
        if status.success?
          container_id = output.to_s.strip
          Log.debug { "Created new container: #{container_id}" }
          container_id
        else
          Log.error { "Failed to create container: #{error.to_s}" }
          nil
        end
      rescue ex
        Log.error { "Error creating container from inspect data: #{ex.message}" }
        nil
      end
    end

    def create_container_with_config(image_name : String, container_name : String, config : Hash(String, JSON::Any)) : String?
      # Get the original container's configuration using docker inspect
      begin
        output = IO::Memory.new
        error = IO::Memory.new
        status = Process.run("docker", ["inspect", container_name],
          output: output, error: error)
        
        unless status.success?
          Log.error { "Failed to inspect container #{container_name}: #{error.to_s}" }
          return nil
        end
        
        # Parse the container inspection output
        container_info = JSON.parse(output.to_s).as_a.first?
        return nil unless container_info
        
        # Extract the container configuration
        config_data = container_info.as_h
        host_config = config_data["HostConfig"]?.try(&.as_h)
        config = config_data["Config"]?.try(&.as_h)
        name = config_data["Name"]?.try(&.as_s)
        
        Log.debug { "Recreating container #{container_name} with original configuration" }
        
        # Build docker create command with original configuration
        create_args = ["create", "--name", container_name]
        
        # Add environment variables
        if config && (env_vars = config["Env"]?.try(&.as_a))
          env_vars.each do |env_var|
            env_str = env_var.as_s
            create_args << "--env"
            create_args << env_str
          end
        end
        
        # Add port mappings
        if host_config && (port_bindings = host_config["PortBindings"]?.try(&.as_h))
          port_bindings.each do |container_port_key, host_bindings|
            container_port = container_port_key.to_s
            if host_bindings.as_a.size > 0
              host_binding = host_bindings.as_a.first.try(&.as_h)
              if host_binding
                host_ip = host_binding["HostIp"]?.try(&.as_s) || ""
                host_port = host_binding["HostPort"]?.try(&.as_s) || ""
                
                port_mapping = if host_ip && !host_ip.empty?
                             "#{host_ip}:#{host_port}:#{container_port}"
                           elsif host_port && !host_port.empty?
                             "#{host_port}:#{container_port}"
                           else
                             container_port
                           end
                
                create_args << "-p"
                create_args << port_mapping
              end
            end
          end
        end
        
        # Add volume mappings
        if host_config && (volume_binds = host_config["Binds"]?.try(&.as_a))
          volume_binds.each do |volume|
            volume_str = volume.as_s
            create_args << "-v"
            create_args << volume_str
          end
        end
        
        # Add network settings
        if config && (exposed_ports = config["ExposedPorts"]?.try(&.as_h))
          exposed_ports.keys.each do |port|
            port_str = port.to_s
            create_args << "--expose"
            create_args << port_str
          end
        end
        
        # Add restart policy
        if host_config && (restart_policy = host_config["RestartPolicy"]?.try(&.as_h))
          policy_name = restart_policy["Name"]?.try(&.as_s)
          if policy_name && policy_name != "no"
            create_args << "--restart"
            create_args << policy_name
          end
        end
        
        # Add the new image
        create_args << image_name
        
        Log.debug { "Docker create command: docker #{create_args.join(" ")}" }
        
        # Execute the docker create command
        output = IO::Memory.new
        error = IO::Memory.new
        status = Process.run("docker", create_args,
          output: output, error: error)
        
        if status.success?
          container_id = output.to_s.strip
          Log.debug { "Created new container: #{container_id}" }
          container_id
        else
          Log.error { "Failed to create container: #{error.to_s}" }
          nil
        end
      rescue ex
        Log.error { "Error creating container with config: #{ex.message}" }
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
      config_output = IO::Memory.new
      config_error = IO::Memory.new
      config_status = Process.run("docker", ["inspect", container_name],
        output: config_output, error: config_error)
      
      unless config_status.success?
        Log.error { "Failed to inspect container #{container_name} for configuration: #{config_error.to_s}" }
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
      @api.containers.inspect(container_id)
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

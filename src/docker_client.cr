require "./docr_workarounds"
require "./types"
require "./error_handling"
require "./constants"
require "./container_name_utils"

module Mangrullo
  # Custom Docker client that supports configurable socket paths
  class CustomDockerClient < Docr::Client
    def initialize(socket_path : String = Mangrullo::Constants::Docker::DEFAULT_SOCKET_PATH)
      socket = UNIXSocket.new(socket_path)
      @client = HTTP::Client.new(socket)
    end
  end

  class DockerClient
    @api : Docr::API

    # Global mutex to prevent concurrent Docker API access across all instances
    @@api_mutex = Mutex.new

    # Retry configuration
    MAX_RETRIES =   3
    BASE_DELAY  = 0.1 # seconds
    MAX_DELAY   = 5.0 # seconds

    def initialize(socket_path : String = Mangrullo::Constants::Docker::DEFAULT_SOCKET_PATH)
      client = CustomDockerClient.new(socket_path)
      @api = Docr::API.new(client)
    end

    private def handle_docker_errors(operation : String, context : String? = nil, &)
      ErrorHandling.docker_api_operation(operation, context) do
        result = yield
        result
      end
    end

    private def handle_docker_errors_with_nil(operation : String, context : String? = nil, &)
      ErrorHandling.docker_api_operation_with_nil(operation, context) do
        result = yield
        result
      end
    end

    private def handle_docker_errors_typed(operation : String, context : String? = nil, &)
      ErrorHandling.docker_api_operation_typed(operation, context) do
        result = yield
        result
      end
    end

    # Execute Docker API operations with global mutex protection
    private def with_docker_api_lock(operation : String, &)
      @@api_mutex.synchronize do
        Log.debug { "Docker API [LOCKED]: #{operation}" }
        begin
          result = yield
          Log.debug { "Docker API [UNLOCKED]: #{operation} - success" }
          result
        rescue ex
          Log.debug { "Docker API [UNLOCKED]: #{operation} - error: #{ex.message}" }
          raise ex
        end
      end
    end

    # Execute Docker API operations with retry logic for malformed responses
    private def with_retry_and_lock(operation : String, retry_on_malformed : Bool = true, &)
      attempt = 0

      while attempt <= MAX_RETRIES
        begin
          return with_docker_api_lock(operation) { yield }
        rescue ex : JSON::ParseException | Docr::Errors::DockerAPIError
          # Check if this is a malformed response error
          if retry_on_malformed && should_retry_on_error?(ex) && attempt < MAX_RETRIES
            attempt += 1
            delay = calculate_backoff(attempt)
            Log.warn { "Docker API malformed response on attempt #{attempt}/#{MAX_RETRIES} for #{operation}. Retrying in #{delay}s..." }
            sleep delay.seconds
          else
            Log.error { "Docker API failed after #{attempt + 1} attempts for #{operation}: #{ex.message}" }
            raise ex
          end
        rescue ex
          # For other exceptions, don't retry
          Log.debug { "Docker API non-retryable error for #{operation}: #{ex.message}" }
          raise ex
        end
      end
    end

    # Determine if an error should trigger a retry
    private def should_retry_on_error?(ex : Exception) : Bool
      case ex
      when JSON::ParseException
        # Always retry JSON parse errors - these indicate malformed responses
        true
      when Docr::Errors::DockerAPIError
        # Retry Docker API errors that suggest malformed responses
        message = ex.message.to_s.downcase
        message.includes?("invalid http response") ||
          message.includes?("unsupported http version") ||
          message.includes?("malformed") ||
          message.includes?("unexpected end") ||
          message.includes?("protocol error")
      else
        false
      end
    end

    # Calculate exponential backoff delay
    private def calculate_backoff(attempt : Int) : Float64
      delay = BASE_DELAY * (2 ** (attempt - 1))
      Math.min(delay, MAX_DELAY)
    end

    def list_containers(all : Bool = false, filters : Hash(String, Array(String)) = {} of String => Array(String)) : Array(ContainerInfo)
      with_docker_api_lock("list containers") do
        containers = @api.containers.list(all: all)
        containers.map { |container| to_container_info(container) }
      end
    rescue ex : JSON::ParseException | Docr::Errors::DockerAPIError
      # For list_containers, we'll retry malformed responses
      attempt = 0
      while attempt < MAX_RETRIES
        attempt += 1
        if should_retry_on_error?(ex)
          delay = calculate_backoff(attempt)
          Log.warn { "Docker API malformed response on attempt #{attempt}/#{MAX_RETRIES} for list containers. Retrying in #{delay}s..." }
          sleep delay.seconds
          # Retry the operation
          begin
            return with_docker_api_lock("list containers retry") do
              containers = @api.containers.list(all: all)
              containers.map { |container| to_container_info(container) }
            end
          rescue ex
            # Continue retrying
          end
        end
      end
      # If all retries failed, re-raise the original exception
      raise ex
    end

    def get_container_info(container_id : String) : ContainerInfo?
      handle_docker_errors_typed("getting container info", "container_id=#{container_id}") do
        with_retry_and_lock("get container info") do
          containers = @api.containers.list(all: true, filters: {"id" => [container_id]})
          return nil if containers.empty?

          to_container_info(containers.first)
        end
      end.value || nil
    end

    def get_image_info(image_name : String) : ImageInfo?
      handle_docker_errors_typed("getting image info", "image_name=#{image_name}") do
        with_retry_and_lock("get image info") do
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

          ImageInfo.new(
            id: correct_image.id,
            repo_tags: correct_image.repo_tags || [] of String,
            created: Time.unix(correct_image.created),
            size: correct_image.size.to_u64,
            labels: correct_image.labels || {} of String => String
          )
        end
      end.value || nil
    end

    def inspect_image(image_name : String) : String?
      handle_docker_errors_typed("inspecting image", "image_name=#{image_name}") do
        with_retry_and_lock("inspect image") do
          image_inspect = @api.images.inspect(image_name)
          repo_digest = image_inspect.repo_digests.try(&.first?)
          return repo_digest if repo_digest
          nil
        end
      end.value || nil
    end

    def pull_image(image_name : String, tag : String = Mangrullo::Constants::Docker::DEFAULT_IMAGE_TAG) : Bool
      result = handle_docker_errors("pulling image", "image=#{image_name}:#{tag}") do
        with_retry_and_lock("pull image") do
          @api.images.create("#{image_name}:#{tag}")
        end
      end
      result.success?
    end

    def restart_container(container_id : String) : Bool
      result = handle_docker_errors("restarting container", "container_id=#{container_id}") do
        with_retry_and_lock("restart container") do
          @api.containers.restart(container_id)
        end
      end
      result.success?
    end

    def stop_container(container_id : String) : Bool
      result = handle_docker_errors("stopping container", "container_id=#{container_id}") do
        with_retry_and_lock("stop container") do
          @api.containers.stop(container_id)
        end
      end
      result.success?
    end

    def remove_container(container_id : String) : Bool
      result = handle_docker_errors("removing container", "container_id=#{container_id}") do
        with_retry_and_lock("remove container") do
          @api.containers.delete(container_id)
        end
      end
      result.success?
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
      handle_docker_errors_typed("creating container from inspect data", "container=#{container_name}, image=#{image_name}") do
        Log.debug { "Creating container #{container_name} from inspect data with image #{image_name}" }

        # Parse the container inspection output
        container_info = JSON.parse(inspect_data)

        # Extract the container configuration
        config_data = container_info.as_h
        host_config_json = config_data["HostConfig"]?.try(&.as_h)
        config_json = config_data["Config"]?.try(&.as_h)

        return nil unless config_json

        # Build the container config
        container_config = Docr::Types::CreateContainerConfig.from_json(config_json.to_json)
        container_config.image = image_name

        if host_config_json
          Log.debug { "HostConfig JSON: #{host_config_json.to_json}" }
          host_config = Docr::Types::HostConfig.from_json(host_config_json.to_json)
          Log.debug { "Parsed NetworkMode: #{host_config.network_mode.inspect}" }

          # Ensure network mode is preserved
          if network_mode = host_config_json["NetworkMode"]?.try(&.as_s)
            Log.info { "Preserving network mode: #{network_mode}" }
            host_config.network_mode = network_mode
          end

          container_config.host_config = host_config
        end

        # Create the container
        with_retry_and_lock("create container") do
          response = @api.containers.create(container_name, container_config)
          response.id
        end
      end
        .value || nil
    end

    def create_container_with_config(image_name : String, container_name : String, config : Hash(String, JSON::Any)) : String?
      handle_docker_errors_typed("creating container with config", "container=#{container_name}, image=#{image_name}") do
        # Get the original container's configuration using docker inspect
        inspect_data = inspect_container(container_name)

        unless inspect_data
          Log.error { "Failed to inspect container #{container_name} for configuration" }
          return nil
        end

        # Parse the container inspection output
        container_info = JSON.parse(inspect_data)

        # Extract the container configuration
        config_data = container_info.as_h
        host_config_json = config_data["HostConfig"]?.try(&.as_h)
        config_json = config_data["Config"]?.try(&.as_h)

        return nil unless config_json

        # Build the container config
        container_config = Docr::Types::CreateContainerConfig.from_json(config_json.to_json)
        container_config.image = image_name

        if host_config_json
          Log.debug { "HostConfig JSON: #{host_config_json.to_json}" }
          host_config = Docr::Types::HostConfig.from_json(host_config_json.to_json)
          Log.debug { "Parsed NetworkMode: #{host_config.network_mode.inspect}" }

          # Ensure network mode is preserved
          if network_mode = host_config_json["NetworkMode"]?.try(&.as_s)
            Log.info { "Preserving network mode: #{network_mode}" }
            host_config.network_mode = network_mode
          end

          container_config.host_config = host_config
        end

        # Create the container
        with_retry_and_lock("create container") do
          response = @api.containers.create(container_name, container_config)
          response.id
        end
      end
        .value || nil
    end

    def start_container(container_id : String) : Bool
      result = handle_docker_errors("starting container", "container_id=#{container_id}") do
        with_retry_and_lock("start container") do
          @api.containers.start(container_id)
        end
      end
      result.success?
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

    def get_container_logs(container_id : String, tail : Int32 = Mangrullo::Constants::Docker::DEFAULT_LOG_TAIL) : String
      result = handle_docker_errors_typed("getting container logs", "container_id=#{container_id}, tail=#{tail}") do
        with_retry_and_lock("get container logs") do
          @api.containers.logs(container_id, tail: tail.to_s).gets_to_end
        end
      end
      result.value || ""
    end

    def inspect_container(container_id : String) : String?
      handle_docker_errors_typed("inspecting container", "container_id=#{container_id}") do
        with_retry_and_lock("inspect container") do
          @api.containers.inspect(container_id).to_json
        end
      end
        .value || nil
    end

    private def to_container_info(container : Docr::Types::ContainerSummary) : ContainerInfo
      container_name = Mangrullo::ContainerNameUtils.normalize_name(container)

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

    private def normalize_container_name(container) : String
      Mangrullo::ContainerNameUtils.normalize_name(container)
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

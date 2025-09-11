require "./container_state"
require "./docker_client"
require "./image_checker"
require "./constants"

module Mangrullo
  # Manages background updates of container state
  class StateManager
    # Singleton instance
    @@instance : StateManager?

    # Get the singleton instance
    def self.instance : StateManager
      @@instance ||= new
    end

    # Reset the singleton (mainly for testing)
    def self.reset
      @@instance = nil
    end

    @docker_client : DockerClient
    @image_checker : ImageChecker
    @update_fiber : Fiber?
    @running : Bool = false
    @update_interval : Time::Span

    private def initialize(
      socket_path : String = Constants::Docker::DEFAULT_SOCKET_PATH,
      update_interval : Int32 = Constants::Config::UPDATE_CHECK_INTERVAL,
    )
      @docker_client = DockerClient.new(socket_path)
      @image_checker = ImageChecker.new(@docker_client)
      @update_interval = update_interval.seconds
      @running = false
    end

    # Start the background updater
    def start
      return if @running

      @running = true
      @update_fiber = spawn do
        Log.info { "StateManager: Starting background update fiber" }

        while @running
          begin
            update_all_containers
          rescue ex
            Log.error { "StateManager: Error in background update: #{ex.message}" }
            ContainerState.instance.last_error = "Background update failed: #{ex.message}"
          end

          sleep @update_interval
        end

        Log.info { "StateManager: Background update fiber stopped" }
      end
    end

    # Stop the background updater
    def stop
      return unless @running

      @running = false
      @update_fiber = nil
      Log.info { "StateManager: Stop signal sent" }
    end

    # Force an immediate update (for manual refresh)
    def force_update : Bool
      return false if ContainerState.instance.update_in_progress?

      begin
        # Run update in a separate fiber to avoid blocking
        spawn do
          update_all_containers
        end
        true
      rescue ex
        Log.error { "StateManager: Failed to start forced update: #{ex.message}" }
        false
      end
    end

    # Force update for a specific container
    def force_update_container(container_id : String) : Bool
      return false if ContainerState.instance.update_in_progress?

      begin
        # Run update in a separate fiber
        spawn do
          update_single_container(container_id)
        end
        true
      rescue ex
        Log.error { "StateManager: Failed to start container update: #{ex.message}" }
        false
      end
    end

    private def update_all_containers
      Log.info { "StateManager: Starting full container update" }
      ContainerState.instance.update_in_progress = true

      # Get all running containers
      containers = @docker_client.running_containers

      if containers.empty?
        Log.info { "StateManager: No running containers found" }
        ContainerState.instance.update_containers([] of ContainerInfo)
        ContainerState.instance.update_in_progress = false
        return
      end

      Log.info { "StateManager: Found #{containers.size} running containers" }

      # Update the container list first
      ContainerState.instance.update_containers(containers)

      # Now check each container for updates
      containers.each do |container|
        begin
          update_info = get_container_update_info(container)
          ContainerState.instance.update_container_update_info(container.id, update_info)
        rescue ex
          Log.error { "StateManager: Failed to check updates for #{container.name}: #{ex.message}" }
          # Set error state for this container
          ContainerState.instance.update_container_update_info(
            container.id,
            {
              needs_update:   false,
              reason:         "Error checking for updates",
              local_version:  nil,
              remote_version: nil,
              last_checked:   Time.utc,
            }
          )
        end
      end

      Log.info { "StateManager: Completed update for #{containers.size} containers" }
      ContainerState.instance.set_update_in_progress(false)
    end

    private def update_single_container(container_id : String)
      Log.info { "StateManager: Updating single container: #{container_id}" }

      # First get the container info
      container = @docker_client.get_container_info(container_id)
      unless container
        Log.warn { "StateManager: Container not found: #{container_id}" }
        return
      end

      # Update the container in state
      containers = ContainerState.instance.containers.map(&.container)
      unless containers.any? { |cont| cont.id == container_id }
        # This container is new, refresh the whole list
        update_all_containers
        return
      end

      # Check for updates
      begin
        update_info = get_container_update_info(container)
        ContainerState.instance.update_container_update_info(container_id, update_info)
        Log.info { "StateManager: Updated single container: #{container.name}" }
      rescue ex
        Log.error { "StateManager: Failed to update #{container.name}: #{ex.message}" }
        ContainerState.instance.update_container_update_info(
          container_id,
          {
            needs_update:   false,
            reason:         "Error checking for updates",
            local_version:  nil,
            remote_version: nil,
            last_checked:   Time.utc,
          }
        )
      end
    end

    private def get_container_update_info(container : ContainerInfo) : NamedTuple(
      needs_update: Bool,
      reason: String?,
      local_version: String?,
      remote_version: String?,
      last_checked: Time?)
      # Use the image checker to get update information
      needs_update = @image_checker.needs_update?(container)

      if needs_update
        # Get detailed update info
        update_info = @image_checker.get_image_update_info(container.image)

        {
          needs_update:   true,
          reason:         generate_update_reason(container, update_info),
          local_version:  update_info[:local_version].try(&.to_s),
          remote_version: update_info[:remote_version].try(&.to_s),
          last_checked:   Time.utc,
        }
      else
        {
          needs_update:   false,
          reason:         nil,
          local_version:  nil,
          remote_version: nil,
          last_checked:   Time.utc,
        }
      end
    end

    private def generate_update_reason(container : ContainerInfo, update_info) : String
      if update_info[:local_version] && update_info[:remote_version]
        local_str = update_info[:local_version].to_s
        remote_str = update_info[:remote_version].to_s
        "Version update available: #{local_str} -> #{remote_str}"
      else
        "Update available for #{container.image}"
      end
    end

    # Get current status information
    def status : NamedTuple(
      running: Bool,
      last_update: Time?,
      container_count: Int32,
      needing_update: Int32,
      update_in_progress: Bool,
      last_error: String?)
      state = ContainerState.instance
      {
        running:            @running,
        last_update:        state.last_update,
        container_count:    state.container_count,
        needing_update:     state.containers_needing_update.size,
        update_in_progress: state.update_in_progress?,
        last_error:         state.last_error,
      }
    end

    # Expose the docker client for operations that need direct access
    def docker_client : DockerClient
      @docker_client
    end
  end
end

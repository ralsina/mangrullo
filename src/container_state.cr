require "./types"
require "time"

module Mangrullo
  # Thread-safe container for all Docker container state
  class ContainerState
    # Container data with update information
    struct ContainerData
      property container : ContainerInfo
      property update_info : NamedTuple(
        needs_update: Bool,
        reason: String?,
        local_version: String?,
        remote_version: String?,
        last_checked: Time?)?
      property last_update_attempt : Time?

      def initialize(@container, @update_info = nil, @last_update_attempt = nil)
      end
    end

    # Singleton instance
    @@instance : ContainerState?

    # Get the singleton instance
    def self.instance : ContainerState
      @@instance ||= new
    end

    # Reset the singleton (mainly for testing)
    def self.reset
      @@instance = nil
    end

    # Internal state
    @containers : Hash(String, ContainerData)
    @mutex : Mutex
    @last_full_update : Time?
    @update_in_progress : Bool
    @last_error : String?

    private def initialize
      @containers = {} of String => ContainerData
      @mutex = Mutex.new
      @last_full_update = nil
      @update_in_progress = false
      @last_error = nil
    end

    # Get all containers thread-safely
    def containers : Array(ContainerData)
      @mutex.synchronize do
        @containers.values
      end
    end

    # Get a specific container by ID
    def container(container_id : String) : ContainerData?
      @mutex.synchronize do
        @containers[container_id]?
      end
    end

    # Update containers atomically
    def update_containers(containers : Array(ContainerInfo))
      @mutex.synchronize do
        # Merge new container data
        containers.each do |container|
          if existing = @containers[container.id]?
            # Preserve existing update info if container hasn't changed
            @containers[container.id] = ContainerData.new(
              container,
              existing.update_info,
              existing.last_update_attempt
            )
          else
            # New container
            @containers[container.id] = ContainerData.new(container)
          end
        end

        # Remove containers that no longer exist
        existing_ids = @containers.keys
        current_ids = containers.map(&.id)
        (existing_ids - current_ids).each do |removed_id|
          @containers.delete(removed_id)
        end

        @last_full_update = Time.utc
        @last_error = nil
      end
    end

    # Update container update info
    def update_container_update_info(container_id : String, update_info)
      @mutex.synchronize do
        if container = @containers[container_id]?
          @containers[container_id] = ContainerData.new(
            container.container,
            update_info,
            Time.utc
          )
        end
      end
    end

    # Mark update attempt for a container
    def mark_update_attempt(container_id : String)
      @mutex.synchronize do
        if container = @containers[container_id]?
          @containers[container_id] = ContainerData.new(
            container.container,
            container.update_info,
            Time.utc
          )
        end
      end
    end

    # Get last full update time
    def last_update : Time?
      @mutex.synchronize do
        @last_full_update
      end
    end

    # Check if update is in progress
    def update_in_progress? : Bool
      @mutex.synchronize do
        @update_in_progress
      end
    end

    # Set update in progress status
    def update_in_progress=(in_progress : Bool)
      @mutex.synchronize do
        @update_in_progress = in_progress
        @last_error = nil unless in_progress
      end
    end

    # Set last error
    def last_error=(error : String)
      @mutex.synchronize do
        @last_error = error
        @update_in_progress = false
      end
    end

    # Get last error
    def last_error : String?
      @mutex.synchronize do
        @last_error
      end
    end

    # Get container count
    def container_count : Int32
      @mutex.synchronize do
        @containers.size
      end
    end

    # Get containers needing updates
    def containers_needing_update : Array(ContainerData)
      @mutex.synchronize do
        @containers.values.select do |data|
          data.update_info.try(&.[:needs_update]) == true
        end
      end
    end

    # Remove a specific container (e.g., when it's recreated with a new ID)
    def remove_container(container_id : String)
      @mutex.synchronize do
        @containers.delete(container_id)
      end
    end

    # Clear all data (for testing or reset)
    def clear
      @mutex.synchronize do
        @containers.clear
        @last_full_update = nil
        @update_in_progress = false
        @last_error = nil
      end
    end
  end
end

module Mangrullo
  # Helper module for accessing container state consistently
  module ContainerStateHelper
    # Get container data by ID
    def self.get_container(container_id : String) : ContainerState::ContainerData?
      ContainerState.instance.container(container_id)
    end

    # Get all containers
    def self.all_containers : Array(ContainerState::ContainerData)
      ContainerState.instance.containers
    end

    # Check if container exists
    def self.container_exists?(container_id : String) : Bool
      ContainerState.instance.container(container_id) != nil
    end

    # Get container update info
    def self.get_update_info(container_id : String) : NamedTuple(
      needs_update: Bool,
      reason: String?,
      local_version: String?,
      remote_version: String?,
      last_checked: Time?)?
      container_data = get_container(container_id)
      container_data.update_info if container_data
    end

    # Check if container needs update
    def self.needs_update?(container_id : String) : Bool
      update_info = get_update_info(container_id)
      update_info ? update_info[:needs_update] : false
    end

    # Get container status
    def self.get_status(container_id : String) : String?
      container_data = get_container(container_id)
      container_data.container.status if container_data
    end

    # Get container image
    def self.get_image(container_id : String) : String?
      container_data = get_container(container_id)
      container_data.container.image if container_data
    end

    # Get containers that need updates
    def self.containers_needing_updates : Array(ContainerState::ContainerData)
      all_containers.select do |data|
        update_info = data.update_info
        update_info && update_info[:needs_update] == true
      end
    end

    # Get container count statistics
    def self.container_stats : NamedTuple(total: Int32, need_updates: Int32)
      containers = all_containers
      total = containers.size
      need_updates = containers_needing_updates.size

      {total: total, need_updates: need_updates}
    end

    # Check if any updates are in progress
    def self.updates_in_progress? : Bool
      ContainerState.instance.update_in_progress?
    end

    # Force update a specific container
    def self.force_update_container(container_id : String) : Bool
      ContainerState.instance.force_update_container(container_id)
    end

    # Remove a container from state
    def self.remove_container(container_id : String) : Void
      ContainerState.instance.remove_container(container_id)
    end

    # Get containers filtered by status
    def self.get_containers_by_status(status : String) : Array(ContainerState::ContainerData)
      all_containers.select do |data|
        data.container.status == status
      end
    end

    # Get running containers
    def self.running_containers : Array(ContainerState::ContainerData)
      get_containers_by_status("running")
    end

    # Get stopped containers
    def self.stopped_containers : Array(ContainerState::ContainerData)
      get_containers_by_status("exited")
    end
  end
end

require "./types"
require "./docker_client"
require "./error_handling"

module Mangrullo
  # Container filtering and normalization utilities
  module ContainerFilter
    # Normalize container name (ensure leading slash)
    def self.normalize_container_name(name : String) : String
      name.starts_with?("/") ? name : "/#{name}"
    end

    # Denormalize container name (remove leading slash for display)
    def self.denormalize_container_name(name : String) : String
      name.lchop('/')
    end

    # Filter containers by name list
    def self.filter_containers_by_name(containers : Array(ContainerInfo), container_names : Array(String)) : Array(ContainerInfo)
      return containers if container_names.empty?

      normalized_input_names = container_names.map { |name| normalize_container_name(name) }

      containers.select do |container|
        normalized_input_names.includes?(container.name) ||
          normalized_input_names.includes?(container.name.lchop('/'))
      end
    end

    # Get running containers with optional name filtering
    def self.get_running_containers_filtered(docker_client : DockerClient, container_names : Array(String) = [] of String) : Array(ContainerInfo)
      result = docker_client.running_containers
      return [] of ContainerInfo unless result.success?

      containers = result.value || [] of ContainerInfo
      filter_containers_by_name(containers, container_names)
    end

    # Get container by name (normalized)
    def self.get_container_by_name(containers : Array(ContainerInfo), name : String) : ContainerInfo?
      normalized_name = normalize_container_name(name)

      containers.find do |container|
        container.name == normalized_name ||
          container.name.lchop('/') == normalized_name.lchop('/')
      end
    end

    # Check if container exists in list (flexible matching)
    def self.container_exists?(containers : Array(ContainerInfo), name : String) : Bool
      !get_container_by_name(containers, name).nil?
    end

    # Filter containers by status
    def self.filter_containers_by_status(containers : Array(ContainerInfo), status : String) : Array(ContainerInfo)
      case status.downcase
      when "running"
        containers.select { |container| container.status.includes?("running") || container.status.includes?("Up") }
      when "stopped"
        containers.select { |container| container.status.includes?("stopped") || container.status.includes?("Exited") }
      when "paused"
        containers.select(&.status.includes?("paused"))
      when "restarting"
        containers.select(&.status.includes?("restarting"))
      else
        containers
      end
    end

    # Filter containers by image pattern
    def self.filter_containers_by_image(containers : Array(ContainerInfo), image_pattern : String) : Array(ContainerInfo)
      regex = Regex.new(image_pattern, Regex::Options::IGNORE_CASE)
      containers.select { |container| regex.matches?(container.image) }
    end

    # Sort containers by name
    def self.sort_containers_by_name(containers : Array(ContainerInfo), ascending : Bool = true) : Array(ContainerInfo)
      containers.sort_by(&.name.lchop('/'))
    end

    # Sort containers by image
    def self.sort_containers_by_image(containers : Array(ContainerInfo), ascending : Bool = true) : Array(ContainerInfo)
      containers.sort_by(&.image)
    end

    # Sort containers by status
    def self.sort_containers_by_status(containers : Array(ContainerInfo), ascending : Bool = true) : Array(ContainerInfo)
      containers.sort_by(&.status)
    end

    # Group containers by status
    def self.group_containers_by_status(containers : Array(ContainerInfo)) : Hash(String, Array(ContainerInfo))
      groups = Hash(String, Array(ContainerInfo)).new do |hash, key|
        hash[key] = [] of ContainerInfo
      end

      containers.each do |container|
        # Determine status category
        status_category = if container.status.includes?("running") || container.status.includes?("Up")
                            "running"
                          elsif container.status.includes?("stopped") || container.status.includes?("Exited")
                            "stopped"
                          elsif container.status.includes?("paused")
                            "paused"
                          elsif container.status.includes?("restarting")
                            "restarting"
                          else
                            "other"
                          end

        groups[status_category] << container
      end

      groups
    end

    # Validate container names exist
    def self.validate_container_names(docker_client : DockerClient, container_names : Array(String)) : Tuple(Array(String), Array(String))
      return {container_names, [] of String} if container_names.empty?

      # Get all containers
      begin
        containers = docker_client.running_containers
      rescue
        # If there's an error getting containers, treat all as invalid
        return {[] of String, container_names}
      end

      # Check which names exist
      valid_names = [] of String
      invalid_names = [] of String

      container_names.each do |name|
        if container_exists?(containers, name)
          valid_names << name
        else
          invalid_names << name
        end
      end

      {valid_names, invalid_names}
    end

    # Get container name suggestions for invalid names
    def self.get_name_suggestions(containers : Array(ContainerInfo), invalid_name : String) : Array(String)
      suggestions = [] of String

      containers.each do |container|
        display_name = container.name.lchop('/')
        if display_name.downcase.includes?(invalid_name.downcase)
          suggestions << display_name
        end
      end

      suggestions.first(5) # Return top 5 suggestions
    end
  end
end

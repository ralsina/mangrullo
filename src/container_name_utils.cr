module Mangrullo
  # Utility methods for container name normalization and formatting
  module ContainerNameUtils
    # Get a normalized container name from a container info object
    def self.normalize_name(container_info) : String
      if container_info.responds_to?(:names) && container_info.names && !container_info.names.empty?
        normalize_name_string(container_info.names.first)
      elsif container_info.responds_to?(:name) && container_info.name && !container_info.name.empty?
        normalize_name_string(container_info.name)
      else
        # Fallback to truncated container ID
        container_id = container_info.id
        truncate_id(container_id)
      end
    end

    # Normalize a container name string (remove leading '/')
    def self.normalize_name_string(name : String) : String
      name.lchop('/')
    end

    # Truncate container ID for display
    def self.truncate_id(container_id : String, length : Int32 = Constants::Docker::CONTAINER_ID_TRUNCATE_LENGTH) : String
      if container_id.size > length
        container_id[0..length - 1]
      else
        container_id
      end
    end

    # Get display name (truncated if too long)
    def self.display_name(name : String, max_length : Int32 = 30) : String
      if name.size > max_length
        name[0..max_length - 3] + "..."
      else
        name
      end
    end
  end
end

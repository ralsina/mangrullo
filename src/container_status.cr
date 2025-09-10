require "./types"
require "./constants"

module Mangrullo
  # Container status classification and display utilities
  module ContainerStatus
    # Status types for containers
    enum StatusType
      UP_TO_DATE
      UPDATE_AVAILABLE
      ERROR
      UNKNOWN
      LATEST_TAG
    end

    # Status information structure
    struct StatusInfo
      property type : StatusType
      property text : String
      property css_class : String?
      property reason : String?

      def initialize(@type : StatusType, @text : String, @css_class : String? = nil, @reason : String? = nil)
      end
    end

    # Get status information for a container
    def self.get_status(container : ContainerInfo, needs_update : Bool?, error : String? = nil) : StatusInfo
      if error
        return StatusInfo.new(StatusType::ERROR, "Error: #{error}", "status-error", error)
      end

      # Check if using latest tag
      if container.image.includes?("latest")
        return StatusInfo.new(StatusType::LATEST_TAG, "Latest Tag", "status-latest", "Using latest tag")
      end

      if needs_update
        return StatusInfo.new(StatusType::UPDATE_AVAILABLE, "Update Available", "status-update-available", "New version available")
      end

      StatusInfo.new(StatusType::UP_TO_DATE, "Up to Date", "status-up-to-date", nil)
    end

    # Get status text for CLI display
    def self.get_cli_status(container : ContainerInfo, needs_update : Bool?, error : String? = nil) : String
      status = get_status(container, needs_update, error)
      status.text
    end

    # Get status CSS class for web display
    def self.get_css_class(container : ContainerInfo, needs_update : Bool?, error : String? = nil) : String?
      status = get_status(container, needs_update, error)
      status.css_class
    end

    # Get status reason for detailed information
    def self.get_reason(container : ContainerInfo, needs_update : Bool?, error : String? = nil) : String?
      status = get_status(container, needs_update, error)
      status.reason
    end

    # Check if a container is up to date
    def self.up_to_date?(container : ContainerInfo, needs_update : Bool?, error : String? = nil) : Bool
      status = get_status(container, needs_update, error)
      status.type == StatusType::UP_TO_DATE || status.type == StatusType::LATEST_TAG
    end

    # Check if a container has an error
    def self.has_error?(container : ContainerInfo, needs_update : Bool?, error : String? = nil) : Bool
      status = get_status(container, needs_update, error)
      status.type == StatusType::ERROR
    end

    # Check if a container needs an update
    def self.needs_update?(container : ContainerInfo, needs_update : Bool?, error : String? = nil) : Bool
      status = get_status(container, needs_update, error)
      status.type == StatusType::UPDATE_AVAILABLE
    end
  end
end

module Mangrullo
  # Centralized constants used throughout the application
  module Constants
    # Docker-related constants
    module Docker
      DEFAULT_SOCKET_PATH          = "/var/run/docker.sock"
      CONTAINER_ID_TRUNCATE_LENGTH =  12
      DEFAULT_LOG_TAIL             = 100
      DEFAULT_IMAGE_TAG            = "latest"
    end

    # HTTP response constants
    module HTTP
      JSON_CONTENT_TYPE     = "application/json"
      TEXT_CONTENT_TYPE     = "text/plain"
      STATUS_OK             = 200
      STATUS_NOT_FOUND      = 404
      STATUS_INTERNAL_ERROR = 500
    end

    # Configuration constants
    module Config
      DEFAULT_INTERVAL      =   300
      UPDATE_CHECK_INTERVAL = 21600 # 6 hours in seconds
      DEFAULT_LOG_LEVEL     = "info"
      VALID_LOG_LEVELS      = ["debug", "info", "warn", "error"]
    end

    # Application constants
    module App
      NAME        = "Mangrullo"
      DESCRIPTION = "Docker container update automation tool"
    end

    # Version parsing constants
    module Version
      SEMVER_MAX_PARTS       =  3
      SEMVER_MIN_PARTS       =  2
      SHA256_TRUNCATE_LENGTH = 12
    end

    # Table display constants
    module Table
      MAX_COLUMN_WIDTH       = 50
      SHA256_PREFIX_TRUNCATE = 47
    end

    # Web UI constants
    module Web
      DEFAULT_PORT        = 3000
      DEFAULT_HOST        = "0.0.0.0"
      REFRESH_INTERVAL    = 30 # seconds
      MAX_CONTAINER_CARDS = 50
    end

    # Registry constants
    module Registry
      DEFAULT_REGISTRY = "docker.io"
      AUTH_HEADER      = "Authorization"
      BEARER_PREFIX    = "Bearer "
    end

    # Self-update exclusion
    module SelfUpdate
      # Container names that should never be updated by mangrullo
      EXCLUDED_NAMES = ["mangrullo", "mangrullo-web"]
    end
  end
end

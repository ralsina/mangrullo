require "./types"

module Mangrullo
  # Standard Result type for consistent error handling
  struct Result(T, E)
    property? success : Bool
    property value : T?
    property error : E?

    def initialize(@success : Bool, @value : T? = nil, @error : E? = nil)
    end
  end

  # Error handling utilities
  module ErrorHandling
    # Log an error with consistent format and return error result
    def self.log_and_return_error(
      operation : String,
      error : Exception,
      log_level : Log::Severity = Log::Severity::Error,
      context : String? = nil,
    ) : Result(Nil, String)
      message = context ? "#{context}: #{operation} failed: #{error.message}" : "#{operation} failed: #{error.message}"

      case log_level
      when Log::Severity::Debug
        Log.debug { message }
      when Log::Severity::Info
        Log.info { message }
      when Log::Severity::Warn
        Log.warn { message }
      when Log::Severity::Error
        Log.error { message }
        begin
          if error.backtrace
            Log.error { error.backtrace.join("\n") }
          end
        rescue
          # Ignore logging errors in tests
        end
      end

      Result(Nil, String).new(false, nil, message)
    end

    # Log a debug message and return error result (for non-critical failures)
    def self.log_debug_and_return_error(
      operation : String,
      error : Exception,
      context : String? = nil,
    ) : Result(Nil, String)
      log_and_return_error(operation, error, Log::Severity::Debug, context)
    end

    # Wrap Docker API operations with consistent error handling
    def self.docker_api_operation(operation : String, context : String? = nil, &) : Result(Bool, String)
      yield
      Result(Bool, String).new(true, true, nil)
    rescue ex : Docr::Errors::DockerAPIError
      full_message = context ? "#{context}: Docker API operation: #{operation} failed: #{ex.message}" : "Docker API operation: #{operation} failed: #{ex.message}"
      Result(Bool, String).new(false, nil, full_message)
    rescue ex : Socket::Error | IO::Error
      log_and_return_error("Network operation: #{operation}", ex, Log::Severity::Error, context)
      Result(Bool, String).new(false, nil, ex.message)
    rescue ex : Exception
      log_and_return_error("Unexpected error in: #{operation}", ex, Log::Severity::Error, context)
      Result(Bool, String).new(false, nil, ex.message)
    end

    # Wrap operations that might return nil, but still want error handling
    def self.docker_api_operation_with_nil(operation : String, context : String? = nil, &) : Result(Nil, String)
      yield
      Result(Nil, String).new(true, nil, nil)
    rescue ex : Docr::Errors::DockerAPIError
      full_message = context ? "#{context}: Docker API operation: #{operation} failed: #{ex.message}" : "Docker API operation: #{operation} failed: #{ex.message}"
      Result(Nil, String).new(false, nil, full_message)
    rescue ex : Socket::Error | IO::Error
      log_and_return_error("Network operation: #{operation}", ex, Log::Severity::Error, context)
    rescue ex : Exception
      log_and_return_error("Unexpected error in: #{operation}", ex, Log::Severity::Error, context)
    end

    # Generic Docker API operation wrapper for operations that return specific types
    def self.docker_api_operation_typed(operation : String, context : String? = nil, &)
      result = yield
      Result.new(true, result, nil)
    rescue ex : Docr::Errors::DockerAPIError
      log_and_return_error("Docker API operation: #{operation}", ex, Log::Severity::Error, context)
      Result.new(false, nil, sanitize_error_message(ex.message))
    rescue ex : Socket::Error | IO::Error
      log_and_return_error("Network operation: #{operation}", ex, Log::Severity::Error, context)
      Result.new(false, nil, sanitize_error_message(ex.message))
    rescue ex : Exception
      log_and_return_error("Unexpected error in: #{operation}", ex, Log::Severity::Error, context)
      Result.new(false, nil, sanitize_error_message(ex.message))
    end

    # Sanitize error messages to prevent malformed output
    def self.sanitize_error_message(message : String?) : String
      return "" if message.nil?
      return "" if message.empty?

      # Remove or replace problematic characters
      sanitized = message.not_nil!.gsub("\0", "")
      sanitized = sanitized.gsub(/[\x01-\x08\x0B\x0C\x0E-\x1F\x7F-\x9F]/, "")

      # Limit length to prevent excessive log spam
      if sanitized.size > 500
        sanitized = "#{sanitized[0..496]}..."
      end

      # Ensure string is valid UTF-8
      sanitized.scrub
    end

    # Wrap HTTP operations with consistent error handling
    def self.http_operation(operation : String, context : String? = nil, &) : Result(HTTP::Client::Response, String)
      result = yield
      Result(HTTP::Client::Response, String).new(true, result, nil)
    rescue ex : Socket::Error | IO::Error
      log_and_return_error("HTTP operation: #{operation}", ex, Log::Severity::Warn, context)
      Result(HTTP::Client::Response, String).new(false, nil, ex.message)
    rescue ex : JSON::ParseException
      log_and_return_error("JSON parsing: #{operation}", ex, Log::Severity::Warn, context)
      Result(HTTP::Client::Response, String).new(false, nil, ex.message)
    rescue ex : Exception
      log_and_return_error("HTTP operation: #{operation}", ex, Log::Severity::Warn, context)
      Result(HTTP::Client::Response, String).new(false, nil, ex.message)
    end

    # Create a success result
    def self.success(value = nil)
      Result(typeof(value), String).new(true, value, nil)
    end

    # Create an error result
    def self.error(message : String, value = nil)
      Result(typeof(value), String).new(false, value, message)
    end

    # Check if a result is successful
    def self.successful?(result) : Bool
      result.success?
    end

    # Check if a result failed
    def self.failed?(result) : Bool
      !result.success?
    end

    # Extract error message from result
    def self.error_message(result) : String?
      result.error
    end

    # Extract value from result
    def self.value(result)
      result.value
    end
  end

  # Custom error types for better error classification
  class MangrulloError < Exception
  end

  class DockerAPIError < MangrulloError
    getter operation : String
    getter context : String?

    def initialize(message : String, @operation : String, @context : String? = nil)
      super(message)
    end
  end

  class RegistryError < MangrulloError
    getter registry_host : String
    getter repository_path : String?

    def initialize(message : String, @registry_host : String, @repository_path : String? = nil)
      super(message)
    end
  end

  class ValidationError < MangrulloError
    getter field : String
    getter value : String

    def initialize(message : String, @field : String, @value : String)
      super(message)
    end
  end
end

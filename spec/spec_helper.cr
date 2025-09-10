require "spec"
require "../src/types"
require "../src/docker_client"
require "../src/image_checker"
require "../src/update_manager"
require "../src/config"
require "../src/cli"

# Setup logging for tests
Log.setup(:none)

# Define VERSION for tests
VERSION = "0.1.0"

# Test helper module
module TestHelper
  # Creates a mock container for testing
  def self.mock_container(id : String, name : String, image : String, status : String = "running")
    Mangrullo::ContainerInfo.new(
      id: id,
      name: name,
      image: image,
      image_id: "sha256:1234567890abcdef",
      labels: {} of String => String,
      status: status,
      created: Time.utc
    )
  end

  # Creates a mock version for testing
  def self.mock_version(major : Int32, minor : Int32, patch : Int32, prerelease : String? = nil)
    Mangrullo::Version.new(major, minor, patch, prerelease)
  end

  # Mock log severity
  def self.with_log_level(level : Log::Severity, &)
    old_level = Log.level
    Log.level = level
    begin
      yield
    ensure
      Log.level = old_level
    end
  end

  # Helper to set environment variables temporarily
  def self.with_env_vars(vars : Hash(String, String), &)
    old_values = {} of String => String?

    # Save old values and set new ones
    vars.each do |key, value|
      old_values[key] = ENV[key]?
      ENV[key] = value
    end

    begin
      yield
    ensure
      # Restore old values
      vars.each_key do |key|
        if value = old_values[key]
          ENV[key] = value
        else
          ENV.delete(key)
        end
      end
    end
  end
end

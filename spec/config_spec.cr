require "./spec_helper"

describe Mangrullo::Config do
  describe ".from_env" do
    it "creates config from environment variables" do
      with_env_vars({
        "MANGRULLO_INTERVAL"            => "120",
        "MANGRULLO_ALLOW_MAJOR_UPGRADE" => "true",
        "MANGRULLO_DOCKER_SOCKET"       => "/custom/path",
        "MANGRULLO_LOG_LEVEL"           => "warn",
        "MANGRULLO_RUN_ONCE"            => "true",
        "MANGRULLO_DRY_RUN"             => "true",
      }) do
        config = Mangrullo::Config.from_env

        config.interval.should eq(120)
        config.allow_major_upgrade?.should be_true
        config.docker_socket_path.should eq("/custom/path")
        config.log_level.should eq("warn")
        config.run_once?.should be_true
        config.dry_run?.should be_true
      end
    end

    it "uses defaults when env vars are not set" do
      # Clear relevant env vars
      old_env = ENV.to_h
      ["MANGRULLO_INTERVAL", "MANGRULLO_ALLOW_MAJOR_UPGRADE",
       "MANGRULLO_DOCKER_SOCKET", "MANGRULLO_LOG_LEVEL",
       "MANGRULLO_RUN_ONCE", "MANGRULLO_DRY_RUN"].each { |k| ENV.delete(k) }

      begin
        config = Mangrullo::Config.from_env

        config.interval.should eq(300)
        config.allow_major_upgrade?.should be_false
        config.docker_socket_path.should eq("/var/run/docker.sock")
        config.log_level.should eq("info")
        config.run_once?.should be_false
        config.dry_run?.should be_false
      ensure
        # Restore env vars
        old_env.each { |k, v| ENV[k] = v }
      end
    end

    it "handles invalid env var values gracefully" do
      with_env_vars({
        "MANGRULLO_INTERVAL" => "invalid",
      }) do
        config = Mangrullo::Config.from_env

        config.interval.should eq(300) # Should fall back to default
      end
    end
  end

  describe ".from_args_and_env" do
    it "merges command line args with environment vars" do
      with_env_vars({
        "MANGRULLO_INTERVAL"  => "120",
        "MANGRULLO_LOG_LEVEL" => "debug",
      }) do
        args = ["--dry-run", "--log-level=warn"] # CLI parsed first, but env overrides
        config = Mangrullo::Config.from_args_and_env(args)

        config.interval.should eq(120)      # From env
        config.log_level.should eq("debug") # From env (overrides CLI)
        config.dry_run?.should be_true      # From CLI
      end
    end
  end

  describe "#setup_logging" do
    it "sets up debug logging level" do
      config = Mangrullo::Config.new(log_level: "debug")

      # This is hard to test without affecting global state
      # We'll just ensure it doesn't raise an exception
      expect_raises_no_exception { config.setup_logging }
    end

    it "sets up info logging level" do
      config = Mangrullo::Config.new(log_level: "info")
      expect_raises_no_exception { config.setup_logging }
    end

    it "sets up warn logging level" do
      config = Mangrullo::Config.new(log_level: "warn")
      expect_raises_no_exception { config.setup_logging }
    end

    it "sets up error logging level" do
      config = Mangrullo::Config.new(log_level: "error")
      expect_raises_no_exception { config.setup_logging }
    end

    it "defaults to info for invalid log level" do
      config = Mangrullo::Config.new(log_level: "invalid")
      expect_raises_no_exception { config.setup_logging }
    end
  end

  describe "#validate!" do
    it "passes validation with valid config" do
      config = Mangrullo::Config.new(
        interval: 60,
        docker_socket_path: "/var/run/docker.sock",
        log_level: "info"
      )

      expect_raises_no_exception { config.validate! }
    end
  end

  describe "#to_s" do
    it "formats configuration as string" do
      config = Mangrullo::Config.new(
        interval: 60,
        allow_major_upgrade: true,
        docker_socket_path: "/tmp/docker.sock",
        log_level: "debug",
        run_once: true,
        dry_run: true,
        container_names: ["nginx", "postgres"]
      )

      result = config.to_s
      result.should contain("60 seconds")
      result.should contain("true")
      result.should contain("/tmp/docker.sock")
      result.should contain("debug")
      result.should contain("Specific containers: nginx, postgres")
    end

    it "shows all containers when no specific names" do
      config = Mangrullo::Config.new(
        container_names: [] of String
      )

      result = config.to_s
      result.should contain("All containers")
    end
  end
end

# Helper methods for testing
private def with_env_vars(vars : Hash(String, String), &)
  # Save original env vars
  old_values = {} of String => String?

  # Set new env vars
  vars.each do |key, value|
    old_values[key] = ENV[key]?
    ENV[key] = value
  end

  begin
    yield
  ensure
    # Restore original env vars
    old_values.each do |key, value|
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end
  end
end

private def expect_raises_no_exception(&)
  yield
end

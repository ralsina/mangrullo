require "docopt-config"
require "./types"
require "./constants"

module Mangrullo
  class Config
    DOCOPT = <<-DOC
    Mangrullo - Docker container update automation tool

    Usage:
      mangrullo [--interval=<seconds>] [--allow-major] [--socket=<path>]
               [--log-level=<level>] [--once] [--dry-run] [<container-name>...]
               [--help] [--version]

    Options:
      --interval=<seconds>   Check interval in seconds [default: #{Mangrullo::Constants::Config::DEFAULT_INTERVAL}]
      --allow-major          Allow major version upgrades
      --socket=<path>        Docker socket path [default: #{Mangrullo::Constants::Docker::DEFAULT_SOCKET_PATH}]
      --log-level=<level>    Log level (debug, info, warn, error) [default: #{Mangrullo::Constants::Config::DEFAULT_LOG_LEVEL}]
      --once                 Run once and exit
      --dry-run              Show what would be updated without actually updating
      --help                 Show this help message
      --version              Show version information

    Arguments:
      <container-name>       Specific container names to check (if not specified, checks all containers)
    DOC

    property interval : Int32
    property? allow_major_upgrade : Bool
    property docker_socket_path : String
    property log_level : String
    property? run_once : Bool
    property? dry_run : Bool
    property container_names : Array(String)

    def initialize(@interval : Int32 = Mangrullo::Constants::Config::DEFAULT_INTERVAL,
                   @allow_major_upgrade : Bool = false,
                   @docker_socket_path : String = Mangrullo::Constants::Docker::DEFAULT_SOCKET_PATH,
                   @log_level : String = Mangrullo::Constants::Config::DEFAULT_LOG_LEVEL,
                   @run_once : Bool = false, @dry_run : Bool = false,
                   @container_names : Array(String) = [] of String)
    end

    def self.parse(args : Array(String), config_file_path : String? = nil) : Config
      version = begin
        ::VERSION
      rescue
        "0.1.0"
      end

      # Use docopt-config to parse with CLI args, env vars, and optional config file
      docopt = Docopt.docopt_config(
        DOCOPT,
        argv: args,
        help: true,
        version: "Mangrullo #{version}",
        env_prefix: "MANGRULLO",
        config_file_path: config_file_path
      )

      # Parse container names
      container_names = if docopt["<container-name>"]?
                          docopt["<container-name>"].as(Array).map(&.as(String))
                        else
                          [] of String
                        end

      # Helper to parse boolean flags
      # When CLI is not provided (false), check env vars
      parse_bool_flag = ->(key : String, env_var : String) {
        value = docopt[key]
        case value
        when Bool
          # If true, CLI explicitly set it; if false, check env var
          value ? true : ENV[env_var]? == "true"
        when String
          value.as(String).downcase == "true"
        else
          # nil or other type, check env var
          ENV[env_var]? == "true"
        end
      }

      # Helper to convert values that might come as strings from env vars
      interval_value = docopt["--interval"]
      interval = case interval_value
                 when Int32
                   interval_value
                 when String
                   interval_value.to_i? || Mangrullo::Constants::Config::DEFAULT_INTERVAL
                 else
                   Mangrullo::Constants::Config::DEFAULT_INTERVAL
                 end

      allow_major_upgrade = parse_bool_flag.call("--allow-major", "MANGRULLO_ALLOW_MAJOR")

      socket_value = docopt["--socket"]
      docker_socket_path = socket_value.as(String)

      log_level_value = docopt["--log-level"]
      log_level = log_level_value.as(String)

      run_once = parse_bool_flag.call("--once", "MANGRULLO_RUN_ONCE")

      dry_run = parse_bool_flag.call("--dry-run", "MANGRULLO_DRY_RUN")

      Config.new(
        interval: interval,
        allow_major_upgrade: allow_major_upgrade,
        docker_socket_path: docker_socket_path,
        log_level: log_level,
        run_once: run_once,
        dry_run: dry_run,
        container_names: container_names
      )
    rescue ex
      puts ex.message
      exit
    end

    def self.from_env : Config
      # This method is kept for backward compatibility but now uses parse
      # with empty args to rely solely on environment variables
      parse([] of String)
    end

    def self.from_args_and_env(args : Array(String)) : Config
      # docopt-config already handles the precedence: CLI > env vars > config file
      # So we can just call parse directly
      parse(args)
    end

    def setup_logging : Void
      case log_level.downcase
      when "debug"
        Log.setup(:debug)
      when "info"
        Log.setup(:info)
      when "warn"
        Log.setup(:warn)
      when "error"
        Log.setup(:error)
      else
        Log.setup(:info)
      end
    end

    def validate! : Void
      errors = [] of String

      if interval <= 0
        errors << "Interval must be greater than 0"
      end

      if docker_socket_path.empty?
        errors << "Docker socket path cannot be empty"
      end

      unless Mangrullo::Constants::Config::VALID_LOG_LEVELS.includes?(log_level.downcase)
        errors << "Log level must be one of: #{Mangrullo::Constants::Config::VALID_LOG_LEVELS.join(", ")}"
      end

      unless errors.empty?
        puts "Configuration errors:"
        errors.each { |error| puts "  - #{error}" }
        exit 1
      end
    end

    def to_s : String
      container_info = container_names.empty? ? "All containers" : "Specific containers: #{container_names.join(", ")}"

      <<-CONFIG
      Mangrullo Configuration:
        Interval: #{interval} seconds
        Allow major upgrades: #{allow_major_upgrade?}
        Docker socket: #{docker_socket_path}
        Log level: #{log_level}
        Run once: #{run_once?}
        Dry run: #{dry_run?}
        Target: #{container_info}
      CONFIG
    end
  end
end

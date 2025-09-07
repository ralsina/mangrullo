require "docopt"
require "./types"

module Mangrullo
  class Config
    DOCOPT = <<-DOC
    Mangrullo - Docker container update automation tool

    Usage:
      mangrullo [--interval=<seconds>] [--allow-major] [--socket=<path>] 
               [--log-level=<level>] [--once] [--dry-run] [--help] [--version]

    Options:
      --interval=<seconds>   Check interval in seconds [default: 300]
      --allow-major          Allow major version upgrades
      --socket=<path>        Docker socket path [default: /var/run/docker.sock]
      --log-level=<level>    Log level (debug, info, warn, error) [default: info]
      --once                 Run once and exit
      --dry-run              Show what would be updated without actually updating
      --help                 Show this help message
      --version              Show version information
    DOC

    property interval : Int32
    property allow_major_upgrade : Bool
    property docker_socket_path : String
    property log_level : String
    property run_once : Bool
    property dry_run : Bool

    def initialize(@interval : Int32 = 300, @allow_major_upgrade : Bool = false, 
                   @docker_socket_path : String = "/var/run/docker.sock", 
                   @log_level : String = "info", @run_once : Bool = false, @dry_run : Bool = false)
    end

    def self.parse(args : Array(String)) : Config
      begin
        docopt = Docopt.docopt(DOCOPT, argv: args, help: true, version: "Mangrullo #{::VERSION}")
        
        Config.new(
          interval: docopt["--interval"].as(String).to_i,
          allow_major_upgrade: docopt["--allow-major"].as(Bool | Nil) || false,
          docker_socket_path: docopt["--socket"].as(String),
          log_level: docopt["--log-level"].as(String),
          run_once: docopt["--once"].as(Bool | Nil) || false,
          dry_run: docopt["--dry-run"].as(Bool | Nil) || false
        )
      rescue ex
        puts ex.message
        exit
      end
    end

    def self.from_env : Config
      Config.new(
        interval: ENV["MANGRULLO_INTERVAL"]?.try(&.to_i?) || 300,
        allow_major_upgrade: ENV["MANGRULLO_ALLOW_MAJOR_UPGRADE"]? == "true",
        docker_socket_path: ENV["MANGRULLO_DOCKER_SOCKET"]? || "/var/run/docker.sock",
        log_level: ENV["MANGRULLO_LOG_LEVEL"]? || "info",
        run_once: ENV["MANGRULLO_RUN_ONCE"]? == "true",
        dry_run: ENV["MANGRULLO_DRY_RUN"]? == "true"
      )
    end

    def self.from_args_and_env(args : Array(String)) : Config
      # Parse command line args first, then override with environment variables
      config = parse(args)
      
      # Environment variables override command line arguments
      config.interval = ENV["MANGRULLO_INTERVAL"]?.try(&.to_i?) || config.interval
      config.allow_major_upgrade = ENV["MANGRULLO_ALLOW_MAJOR_UPGRADE"]? == "true" || config.allow_major_upgrade
      config.docker_socket_path = ENV["MANGRULLO_DOCKER_SOCKET"]? || config.docker_socket_path
      config.log_level = ENV["MANGRULLO_LOG_LEVEL"]? || config.log_level
      config.run_once = ENV["MANGRULLO_RUN_ONCE"]? == "true" || config.run_once
      config.dry_run = ENV["MANGRULLO_DRY_RUN"]? == "true" || config.dry_run
      
      config
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

      valid_log_levels = ["debug", "info", "warn", "error"]
      unless valid_log_levels.includes?(log_level.downcase)
        errors << "Log level must be one of: #{valid_log_levels.join(", ")}"
      end

      unless errors.empty?
        puts "Configuration errors:"
        errors.each { |error| puts "  - #{error}" }
        exit 1
      end
    end

    def to_s : String
      <<-CONFIG
      Mangrullo Configuration:
        Interval: #{interval} seconds
        Allow major upgrades: #{allow_major_upgrade}
        Docker socket: #{docker_socket_path}
        Log level: #{log_level}
        Run once: #{run_once}
        Dry run: #{dry_run}
      CONFIG
    end
  end
end
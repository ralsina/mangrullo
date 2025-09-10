require "signal"
require "./types"
require "./docker_client"
require "./image_checker"
require "./update_manager"
require "./config"
require "./result_processor"
require "./display_formatter"

module Mangrullo
  class CLI
    property config : Config
    property docker_client : DockerClient
    property update_manager : UpdateManager
    property? running : Bool = true

    def initialize(@config : Config)
      config.setup_logging
      @docker_client = DockerClient.new(config.docker_socket_path)
      @update_manager = UpdateManager.new(@docker_client, config.log_level)

      setup_signal_handlers
    end

    def self.run(args : Array(String))
      config = Config.from_args_and_env(args)
      config.validate!

      cli = CLI.new(config)

      if config.dry_run?
        cli.dry_run
      elsif config.run_once?
        cli.run_once
      else
        cli.run_daemon
      end
    end

    def run_once
      Log.info { "Mangrullo starting (single run)" }
      Log.info { config.to_s }

      begin
        results = update_manager.check_and_update_containers(config.allow_major_upgrade?, config.container_names)

        # Use ResultProcessor to generate summary
        summary = ResultProcessor.generate_summary(results)

        # Only show summary logs in debug mode (table shows the same info)
        Log.debug { "Update check completed" }
        Log.debug { ResultProcessor.format_summary_cli(summary) }

        # Log errors using ResultProcessor
        ResultProcessor.log_errors(results)
      rescue ex : Exception
        Log.error { "Fatal error: #{ex.message}" }
        exit 1
      end
    end

    def run_daemon
      Log.info { "Mangrullo starting (daemon mode)" }
      Log.info { config.to_s }

      while running?
        begin
          Log.info { "Starting update cycle" }
          results = update_manager.check_and_update_containers(config.allow_major_upgrade?, config.container_names)

          # Use ResultProcessor to generate summary
          summary = ResultProcessor.generate_summary(results)

          Log.debug { "Update cycle completed" }
          Log.debug { ResultProcessor.format_summary_cli(summary) }

          # Log errors using ResultProcessor
          ResultProcessor.log_errors(results)

          # Wait for next cycle
          Log.info { "Next check in #{config.interval} seconds" }
          sleep config.interval.seconds
        rescue ex : Exception
          Log.error { "Error in update cycle: #{ex.message}" }
          Log.error { "Retrying in #{config.interval} seconds" }
          sleep config.interval.seconds
        end
      end

      Log.info { "Mangrullo shutting down" }
    end

    def dry_run
      Log.info { "Mangrullo dry run" }
      Log.info { config.to_s }

      begin
        results = update_manager.dry_run(config.allow_major_upgrade?, config.container_names)

        # Use ResultProcessor for unified results
        summary = ResultProcessor.generate_unified_summary(results)
        needing_update = ResultProcessor.filter_unified_by_status(results, :needs_update)

        # Only show detailed logs in debug mode (table shows the same info)
        Log.debug { "Dry run results:" }
        Log.debug { ResultProcessor.format_summary_cli(summary) }

        if needing_update.empty?
          Log.debug { "All containers are up to date" }
        else
          Log.debug { "Containers needing updates:" }
          needing_update.each do |result|
            Log.debug { "  #{result[:container].name}: #{result[:reason]}" }
          end
        end
      rescue ex : Exception
        Log.error { "Error during dry run: #{ex.message}" }
        exit 1
      end
    end

    private def setup_signal_handlers
      Signal::INT.trap do
        Log.info { "Received SIGINT, shutting down gracefully..." }
        @running = false
      end

      Signal::TERM.trap do
        Log.info { "Received SIGTERM, shutting down gracefully..." }
        @running = false
      end
    end
  end
end

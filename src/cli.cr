require "signal"
require "./types"
require "./docker_client"
require "./image_checker"
require "./update_manager"
require "./config"

module Mangrullo
  class CLI
    property config : Config
    property docker_client : DockerClient
    property update_manager : UpdateManager
    property? running : Bool = true

    def initialize(@config : Config)
      config.setup_logging
      @docker_client = DockerClient.new(config.docker_socket_path)
      @update_manager = UpdateManager.new(@docker_client)

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

        updated_count = results.count { |result| result[:updated] }
        error_count = results.count { |result| result[:error] }

        Log.info { "Update check completed" }
        Log.info { "Containers checked: #{results.size}" }
        Log.info { "Containers updated: #{updated_count}" }
        Log.info { "Errors encountered: #{error_count}" }

        if error_count > 0
          Log.error { "Some containers failed to update:" }
          results.each do |result|
            if result[:error]
              Log.error { "  #{result[:container].name}: #{result[:error]}" }
            end
          end
        end
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

          updated_count = results.count { |result| result[:updated] }
          error_count = results.count { |result| result[:error] }

          Log.info { "Update cycle completed" }
          Log.info { "Containers checked: #{results.size}" }
          Log.info { "Containers updated: #{updated_count}" }
          Log.info { "Errors encountered: #{error_count}" }

          if error_count > 0
            Log.error { "Some containers failed to update:" }
            results.each do |result|
              if result[:error]
                Log.error { "  #{result[:container].name}: #{result[:error]}" }
              end
            end
          end

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

        needing_update = results.select { |result| result[:needs_update] }

        Log.info { "Dry run results:" }
        Log.info { "Containers checked: #{results.size}" }
        Log.info { "Containers needing updates: #{needing_update.size}" }

        if needing_update.empty?
          Log.info { "All containers are up to date" }
        else
          Log.info { "Containers needing updates:" }
          needing_update.each do |result|
            Log.info { "  #{result[:container].name}: #{result[:reason]}" }
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

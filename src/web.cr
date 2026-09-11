require "kemal"
require "baked_file_handler"
require "./static_assets"
require "./web_server"
require "./types"
require "./docker_client"
require "./image_checker"
require "./update_manager"
require "./constants"
require "./version"

module Mangrullo
  # Web server entry point.
  # The listen address follows the documented MANGRULLO_WEB_PORT and
  # MANGRULLO_WEB_HOST variables; PORT is kept as a generic fallback so the
  # UI can run alongside other services on the default port.
  Kemal.config.port = ENV["MANGRULLO_WEB_PORT"]?.try(&.to_i?) ||
                      ENV["PORT"]?.try(&.to_i?) ||
                      Mangrullo::Constants::Web::DEFAULT_PORT
  Kemal.config.host_binding = ENV["MANGRULLO_WEB_HOST"]? ||
                              Mangrullo::Constants::Web::DEFAULT_HOST

  # Add handler for static files
  add_handler BakedFileHandler::BakedFileHandler.new(StaticAssets)

  # Initialize the web server
  WebServer.new

  # Start Kemal
  Kemal.run do |_|
    puts "Starting Mangrullo Web UI on http://#{Kemal.config.host_binding}:#{Kemal.config.port}"
  end

  # Cleanup on shutdown
  at_exit do
    puts "Shutting down StateManager..."
    Mangrullo::StateManager.instance.stop
  end
end

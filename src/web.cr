require "kemal"
require "kilt"
require "./web_server"
require "./types"
require "./docker_client"
require "./image_checker"
require "./update_manager"
require "./constants"

module Mangrullo
  VERSION = "0.1.0"

  # Web server entry point
  Kemal.config.port = Mangrullo::Constants::Web::DEFAULT_PORT
  Kemal.config.host_binding = Mangrullo::Constants::Web::DEFAULT_HOST

  # Initialize the web server
  WebServer.new

  # Start Kemal
  Kemal.run do |_|
    puts "Starting Mangrullo Web UI on http://#{Kemal.config.host_binding}:#{Kemal.config.port}"
  end
end

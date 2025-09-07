require "kemal"
require "kilt"
require "./web_server"
require "./types"
require "./docker_client"
require "./image_checker"
require "./update_manager"

module Mangrullo
  VERSION = "0.1.0"

  # Web server entry point
  Kemal.config.port = 3000
  Kemal.config.host_binding = "0.0.0.0"

  puts "Starting Mangrullo Web UI on http://0.0.0.0:3000"

  # Initialize the web server
  WebServer.new

  # Start Kemal
  Kemal.run
end

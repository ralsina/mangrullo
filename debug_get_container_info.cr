#!/usr/bin/env crystal

require "docr"
require "./src/docker_client"
require "./src/config"

module Mangrullo
  class DebugCLI
    property docker_client : DockerClient

    def initialize
      # Use default socket path from config
      config = Config.new
      config.setup_logging
      @docker_client = DockerClient.new(config.docker_socket_path)
    end

    def run
      puts "=== Mangrullo Debug CLI - Testing get_container_info ==="
      puts

      # First, get all running containers
      puts "1. Getting all running containers..."
      containers = @docker_client.running_containers
      
      if containers.empty?
        puts "No running containers found."
        return
      end

      puts "Found #{containers.size} running containers:"
      containers.each do |container|
        puts "  - #{container.name} (#{container.id[0..12]}) - #{container.image}"
      end
      puts

      # Now test get_container_info for each container
      puts "2. Testing get_container_info for each container..."
      puts

      containers.each_with_index do |container, index|
        puts "--- Container #{index + 1}/#{containers.size} ---"
        puts "Testing container: #{container.name}"
        puts "Container ID: #{container.id}"
        
        result = @docker_client.get_container_info(container.id)
        
        if result
          puts "✅ SUCCESS: get_container_info returned:"
          puts "  Name: #{result.name}"
          puts "  Image: #{result.image}"
          puts "  Status: #{result.status}"
          puts "  Created: #{result.created}"
        else
          puts "❌ FAILED: get_container_info returned nil"
        end
        
        puts
      end

      puts "=== Debug complete ==="
    rescue ex
      puts "ERROR: #{ex.message}"
      puts ex.backtrace.join("\n") if ex.backtrace
    end
  end
end

# Run the debug CLI
Mangrullo::DebugCLI.new.run
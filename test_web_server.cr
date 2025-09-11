require "kemal"
require "./src/types"
require "./src/docker_client"
require "./src/config"

# Test version that creates new clients per request
class TestWebServer
  def initialize
    setup_routes
  end

  private def setup_routes
    get "/test-container/:id" do |env|
      # Create a NEW DockerClient for each request
      docker_client = Mangrullo::DockerClient.new(Mangrullo::Constants::Docker::DEFAULT_SOCKET_PATH)
      
      container_id = env.params.url["id"]
      puts "=== REQUEST: Getting container info for #{container_id} ==="
      
      container = docker_client.get_container_info(container_id)
      
      if container
        {
          id: container.id,
          name: container.name,
          image: container.image,
          status: container.status
        }.to_json
      else
        env.response.status_code = 404
        {error: "Container not found"}.to_json
      end
    end
    
    get "/health" do
      "OK"
    end
  end
end

# Configure Kemal
Kemal.config.port = 8081
Kemal.config.host_binding = "0.0.0.0"

# Initialize and run
TestWebServer.new

puts "Starting test web server on http://0.0.0.0:8081"
puts "This version creates a new DockerClient per request"

Kemal.run do |_|
  puts "Test server running"
end
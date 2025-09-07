require "kemal"
require "kilt"
require "json"
require "./types"
require "./docker_client"
require "./image_checker"
require "./update_manager"
require "./config"
require "./web_views"

class WebServer
  @docker_client : Mangrullo::DockerClient
  @image_checker : Mangrullo::ImageChecker
  @update_manager : Mangrullo::UpdateManager
  @web_views : WebViews

  def initialize
    @docker_client = Mangrullo::DockerClient.new("/var/run/docker.sock")
    @image_checker = Mangrullo::ImageChecker.new(@docker_client)
    @update_manager = Mangrullo::UpdateManager.new(@docker_client)
    @web_views = WebViews.new

    setup_routes
  end

  private def setup_routes
    # Serve static files
    public_folder "public"

    # Main page
    get "/" do |env|
      containers = @docker_client.running_containers
      @web_views.dashboard(env, containers)
    end

    # Container details
    get "/containers/:id" do |env|
      container_id = env.params.url["id"]
      container = @docker_client.get_container_info(container_id)

      if container
        update_info = @image_checker.get_image_update_info(container.image)
        @web_views.container_details(env, container, update_info)
      else
        env.response.status_code = 404
        "Container not found"
      end
    end

    # Check for updates
    post "/containers/:id/check-update" do |env|
      container_id = env.params.url["id"]
      container = @docker_client.get_container_info(container_id)

      if container
        update_info = @image_checker.get_image_update_info(container.image)
        env.response.content_type = "application/json"
        {
          container_id:   container_id,
          has_update:     update_info[:has_update],
          local_version:  update_info[:local_version].try(&.to_s),
          remote_version: update_info[:remote_version].try(&.to_s),
        }.to_json
      else
        env.response.status_code = 404
        {error: "Container not found"}.to_json
      end
    end

    # Update container
    post "/containers/:id/update" do |env|
      container_id = env.params.url["id"]
      container = @docker_client.get_container_info(container_id)
      allow_major = env.params.body["allow_major"]?.try(&.downcase) == "true"

      if container
        result = @update_manager.update_container(container, allow_major)
        env.response.content_type = "application/json"
        {
          container_id: container_id,
          updated:      result[:updated],
          error:        result[:error],
        }.to_json
      else
        env.response.status_code = 404
        {error: "Container not found"}.to_json
      end
    end

    # Check all containers for updates
    get "/api/updates" do |env|
      allow_major = env.params.query["allow_major"]?.try(&.downcase) == "true"
      containers = @docker_client.running_containers

      results = containers.map do |container|
        {
          id:           container.id,
          name:         container.name,
          image:        container.image,
          needs_update: @image_checker.needs_update?(container, allow_major),
          update_info:  @image_checker.get_image_update_info(container.image),
        }
      end

      env.response.content_type = "application/json"
      results.to_json
    end

    # Update all containers
    post "/api/updates" do |env|
      allow_major = env.params.body["allow_major"]?.try(&.downcase) == "true"
      dry_run = env.params.body["dry_run"]?.try(&.downcase) == "true"

      if dry_run
        results = @update_manager.dry_run(allow_major)
      else
        results = @update_manager.check_and_update_containers(allow_major)
      end

      env.response.content_type = "application/json"
      results.to_json
    end

    # Container logs
    get "/containers/:id/logs" do |env|
      container_id = env.params.url["id"]
      tail = env.params.query["tail"]?.try(&.to_i) || 100

      if @docker_client.container_exists?(container_id)
        logs = @docker_client.get_container_logs(container_id, tail)
        env.response.content_type = "text/plain"
        logs
      else
        env.response.status_code = 404
        "Container not found"
      end
    end

    # Restart container
    post "/containers/:id/restart" do |env|
      container_id = env.params.url["id"]

      if @docker_client.container_exists?(container_id)
        success = @docker_client.restart_container(container_id)
        env.response.content_type = "application/json"
        {success: success}.to_json
      else
        env.response.status_code = 404
        {error: "Container not found"}.to_json
      end
    end

    # Health check
    get "/health" do
      "OK"
    end

    # 404 handler
    error 404 do
      "Page not found"
    end

    # 500 handler
    error 500 do |env, exc|
      puts "Internal server error: #{exc.message}"
      env.response.content_type = "application/json"
      {error: "Internal server error", message: exc.message}.to_json
    end
  end
end

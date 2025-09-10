require "kemal"
require "kilt"
require "json"
require "./types"
require "./docker_client"
require "./image_checker"
require "./update_manager"
require "./config"
require "./web_views"
require "./error_handling"
require "./container_filter"
require "./result_processor"
require "./display_formatter"
require "./constants"

class WebServer
  @docker_client : Mangrullo::DockerClient
  @image_checker : Mangrullo::ImageChecker
  @update_manager : Mangrullo::UpdateManager
  @web_views : WebViews

  def initialize
    @docker_client = Mangrullo::DockerClient.new(Mangrullo::Constants::Docker::DEFAULT_SOCKET_PATH)
    @image_checker = Mangrullo::ImageChecker.new(@docker_client)
    @update_manager = Mangrullo::UpdateManager.new(@docker_client)
    @web_views = WebViews.new(@update_manager)

    setup_routes
  end

  private def handle_web_error(operation : String, env, error : Exception, json_response : Bool = true)
    Mangrullo::ErrorHandling.log_and_return_error(operation, error, Log::Severity::Error, "web_server")

    if json_response
      env.response.status_code = 500
      env.response.content_type = "application/json"
      error_message = case error
                      when Docr::Errors::DockerAPIError
                        "Docker API error"
                      when Socket::Error, IO::Error
                        "Network error"
                      else
                        "Unexpected error"
                      end
      {error: error_message, message: "An error occurred"}.to_json
    else
      env.response.status_code = 500
      case error
      when Docr::Errors::DockerAPIError
        "Error connecting to Docker API. Please check if Docker is running."
      when Socket::Error, IO::Error
        "Network error connecting to Docker. Please check your connection."
      else
        "An unexpected error occurred."
      end
    end
  end

  private def setup_routes
    # Serve static files
    public_folder "public"

    # Main page
    get "/" do |env|
      begin
        containers = @docker_client.running_containers
        @web_views.dashboard(env, containers)
      rescue ex
        handle_web_error("loading dashboard", env, ex, json_response: false)
      end
    end

    # Container details
    get "/containers/:id" do |env|
      begin
        container_id = env.params.url["id"]
        container = @docker_client.get_container_info(container_id)

        if container
          update_info = @image_checker.get_image_update_info(container.image)
          @web_views.container_details(env, container, update_info)
        else
          env.response.status_code = 404
          "Container not found"
        end
      rescue ex
        handle_web_error("getting container details", env, ex, json_response: false)
      end
    end

    # Check for updates
    post "/containers/:id/check-update" do |env|
      begin
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
      rescue ex
        handle_web_error("checking container update", env, ex)
      end
    end

    # Update container
    post "/containers/:id/update" do |env|
      begin
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
      rescue ex
        handle_web_error("updating container", env, ex)
      end
    end

    # Check all containers for updates
    get "/api/updates" do |env|
      begin
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

        env.response.content_type = Mangrullo::Constants::HTTP::JSON_CONTENT_TYPE
        results.to_json
      rescue ex
        handle_web_error("checking all updates", env, ex)
      end
    end

    # Update all containers
    post "/api/updates" do |env|
      begin
        allow_major = env.params.body["allow_major"]?.try(&.downcase) == "true"
        dry_run = env.params.body["dry_run"]?.try(&.downcase) == "true"

        if dry_run
          results = @update_manager.dry_run(allow_major)
        else
          results = @update_manager.check_and_update_containers(allow_major)
        end

        env.response.content_type = Mangrullo::Constants::HTTP::JSON_CONTENT_TYPE
        results.to_json
      rescue ex
        handle_web_error("updating all containers", env, ex)
      end
    end

    # Bulk operation status (for progress tracking)
    get "/api/updates/status/:operation_id" do |env|
      begin
        operation_id = env.params.url["operation_id"]

        # For now, return a simple status
        # In a real implementation, this would track actual operation progress
        env.response.content_type = Mangrullo::Constants::HTTP::JSON_CONTENT_TYPE
        {
          operation_id: operation_id,
          status:       "completed",
          progress:     100,
          message:      "Operation completed",
        }.to_json
      rescue ex
        handle_web_error("getting operation status", env, ex)
      end
    end

    # Container logs
    get "/containers/:id/logs" do |env|
      begin
        container_id = env.params.url["id"]
        tail = env.params.query["tail"]?.try(&.to_i) || Mangrullo::Constants::Docker::DEFAULT_LOG_TAIL

        if @docker_client.container_exists?(container_id)
          logs = @docker_client.get_container_logs(container_id, tail)
          env.response.content_type = "text/plain"
          logs
        else
          env.response.status_code = 404
          "Container not found"
        end
      rescue ex
        handle_web_error("getting container logs", env, ex, json_response: false)
      end
    end

    # Dry run results page
    get "/api/dry-run" do |env|
      begin
        allow_major = env.params.query["allow_major"]?.try(&.downcase) == "true"
        results = @update_manager.dry_run(allow_major)
        @web_views.dry_run_results(env, results, allow_major)
      rescue ex
        handle_web_error("generating dry run results", env, ex, json_response: false)
      end
    end

    # Bulk operations page
    get "/bulk-operations" do |env|
      @web_views.bulk_operations(env)
    end

    # Restart container
    post "/containers/:id/restart" do |env|
      begin
        container_id = env.params.url["id"]

        if @docker_client.container_exists?(container_id)
          success = @docker_client.restart_container(container_id)
          env.response.content_type = "application/json"
          {success: success}.to_json
        else
          env.response.status_code = 404
          {error: "Container not found"}.to_json
        end
      rescue ex
        handle_web_error("restarting container", env, ex)
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
      env.response.content_type = Mangrullo::Constants::HTTP::JSON_CONTENT_TYPE
      {error: "Internal server error", message: exc.message}.to_json
    end
  end
end

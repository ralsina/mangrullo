require "kemal"
require "kilt"
require "json"
require "./types"
require "./container_state"
require "./state_manager"
require "./docker_client"
require "./update_manager"
require "./config"
require "./web_views"
require "./error_handling"
require "./constants"

class WebServer
  @web_views : WebViews
  @update_manager : Mangrullo::UpdateManager

  def initialize
    @update_manager = Mangrullo::UpdateManager.new(Mangrullo::StateManager.instance.docker_client)
    @web_views = WebViews.new(@update_manager)

    # Start the state manager
    Mangrullo::StateManager.instance.start

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
        containers = Mangrullo::ContainerState.instance.get_containers.map(&.container)
        @web_views.dashboard(env, containers)
      rescue ex
        handle_web_error("loading dashboard", env, ex, json_response: false)
      end
    end

    # Container details
    get "/containers/:id" do |env|
      begin
        container_id = env.params.url["id"]
        container_data = Mangrullo::ContainerState.instance.get_container(container_id)

        if container_data
          @web_views.container_details(env, container_data.container, container_data.update_info)
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

        # Trigger update for this specific container
        if Mangrullo::StateManager.instance.force_update_container(container_id)
          env.response.content_type = "application/json"
          {
            container_id: container_id,
            status:       "updating",
            message:      "Update check initiated",
          }.to_json
        else
          env.response.content_type = "application/json"
          {
            container_id: container_id,
            status:       "error",
            message:      "Update already in progress",
          }.to_json
        end
      rescue ex
        handle_web_error("checking container update", env, ex)
      end
    end

    # Update container
    post "/containers/:id/update" do |env|
      begin
        container_id = env.params.url["id"]
        container_data = Mangrullo::ContainerState.instance.get_container(container_id)
        allow_major = env.params.body["allow_major"]?.try(&.downcase) == "true"

        if container_data
          result = @update_manager.update_container(container_data.container, allow_major)
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
        containers = Mangrullo::ContainerState.instance.get_containers

        results = containers.map do |data|
          # Extract update info, considering allow_major preference
          update_info = data.update_info
          needs_update = false

          if update_info
            # Simple version comparison for allow_major
            if allow_major
              needs_update = update_info[:needs_update]
            else
              # Only allow minor/patch updates
              needs_update = update_info[:needs_update] && !major_update?(update_info[:local_version], update_info[:remote_version])
            end
          end

          {
            id:           data.container.id,
            name:         data.container.name,
            image:        data.container.image,
            needs_update: needs_update,
            update_info:  update_info,
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

        # Use the StateManager's docker client
        docker_client = Mangrullo::StateManager.instance.docker_client

        if docker_client.container_exists?(container_id)
          logs = docker_client.get_container_logs(container_id, tail)
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

        # Use the StateManager's docker client
        docker_client = Mangrullo::StateManager.instance.docker_client

        if docker_client.container_exists?(container_id)
          success = docker_client.restart_container(container_id)
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

    # Force refresh all containers
    post "/api/refresh" do |env|
      begin
        if Mangrullo::StateManager.instance.force_update
          env.response.content_type = "application/json"
          {success: true, message: "Refresh initiated"}.to_json
        else
          env.response.content_type = "application/json"
          {success: false, message: "Refresh already in progress"}.to_json
        end
      rescue ex
        handle_web_error("refreshing containers", env, ex)
      end
    end

    # Get system status
    get "/api/status" do |env|
      begin
        status = Mangrullo::StateManager.instance.get_status
        env.response.content_type = "application/json"
        status.to_json
      rescue ex
        handle_web_error("getting status", env, ex)
      end
    end

    # Get all containers with update info
    get "/api/containers" do |env|
      begin
        containers = Mangrullo::ContainerState.instance.get_containers
        env.response.content_type = "application/json"
        containers.map do |data|
          {
            id:          data.container.id,
            name:        data.container.name,
            image:       data.container.image,
            status:      data.container.status,
            created:     data.container.created,
            update_info: data.update_info,
          }
        end.to_json
      rescue ex
        handle_web_error("getting containers", env, ex)
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

  private def major_update?(local_version : String?, remote_version : String?) : Bool
    return false unless local_version && remote_version

    # Extract version numbers (simplified - assumes semantic versioning)
    local_parts = local_version.split(/[^\d]/).reject(&.empty?).map(&.to_i?)
    remote_parts = remote_version.split(/[^\d]/).reject(&.empty?).map(&.to_i?)

    # If we can't parse versions, assume it could be major
    return true if local_parts.size < 2 || remote_parts.size < 2

    # Compare major versions
    local_major = local_parts[0] || 0
    remote_major = remote_parts[0] || 0

    remote_major > local_major
  end
end

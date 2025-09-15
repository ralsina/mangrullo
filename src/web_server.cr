require "kemal"
require "baked_file_handler"
require "./types"
require "./container_state"
require "./state_manager"
require "./docker_client"
require "./update_manager"
require "./update_job_queue"
require "./config"
require "./web_views"
require "./error_handling"
require "./constants"
require "./json_response_helper"
require "./container_name_utils"
require "./container_state_helper"
require "./version_utils"

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
      error_message = case error
                      when Docr::Errors::DockerAPIError
                        "Docker API error"
                      when Socket::Error, IO::Error
                        "Network error"
                      else
                        "Unexpected error"
                      end
      Mangrullo::JsonResponseHelper.send_error(env, error_message, 500, "An error occurred")
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
    setup_page_routes
    setup_container_routes
    setup_api_routes
    setup_error_handlers
  end

  private def setup_page_routes
    # Main page
    get "/" do |env|
      begin
        containers = Mangrullo::ContainerState.instance.containers.map(&.container)
        @web_views.dashboard(env, containers)
      rescue ex
        handle_web_error("loading dashboard", env, ex, json_response: false)
      end
    end
  end

  private def setup_container_routes
    # Check for updates
    post "/containers/:id/check-update" do |env|
      begin
        container_id = env.params.url["id"]

        # Trigger update for this specific container
        if Mangrullo::StateManager.instance.force_update_container(container_id)
          Mangrullo::JsonResponseHelper.send_status(env, "updating", "Update check initiated")
        else
          Mangrullo::JsonResponseHelper.send_error(env, "Update already in progress", 409)
        end
      rescue ex
        handle_web_error("checking container update", env, ex)
      end
    end

    # Update container
    post "/containers/:id/update" do |env|
      begin
        container_id = env.params.url["id"]
        container_data = Mangrullo::ContainerState.instance.container(container_id)
        allow_major = env.params.body["allow_major"]?.try(&.downcase) == "true"

        if container_data
          # Enqueue the update job
          job_queue = Mangrullo::UpdateJobQueue.instance
          container_name = Mangrullo::ContainerNameUtils.normalize_name_string(container_data.container.name)
          job_id = job_queue.enqueue_update(container_id, container_name, allow_major)

          Mangrullo::JsonResponseHelper.send_job_response(env, job_id, container_id, "queued", "Update job queued successfully")
        else
          Mangrullo::JsonResponseHelper.send_error(env, "Container not found", 404)
        end
      rescue ex
        handle_web_error("updating container", env, ex)
      end
    end

    # Restart container
    post "/containers/:id/restart" do |env|
      begin
        container_id = env.params.url["id"]

        # Use the StateManager's docker client
        docker_client = Mangrullo::StateManager.instance.docker_client

        if docker_client.container_exists?(container_id)
          success = docker_client.restart_container(container_id)
          Mangrullo::JsonResponseHelper.send_success(env, {success: success})
        else
          Mangrullo::JsonResponseHelper.send_error(env, "Container not found", 404)
        end
      rescue ex
        handle_web_error("restarting container", env, ex)
      end
    end
  end

  private def setup_api_routes
    # Check all containers for updates
    get "/api/updates" do |env|
      begin
        allow_major = env.params.query["allow_major"]?.try(&.downcase) == "true"
        containers = Mangrullo::ContainerState.instance.containers

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

    # Force refresh all containers
    post "/api/refresh" do |env|
      begin
        if Mangrullo::StateManager.instance.force_update
          Mangrullo::JsonResponseHelper.send_success(env, {message: "Refresh initiated"})
        else
          Mangrullo::JsonResponseHelper.send_error(env, "Refresh already in progress", 409)
        end
      rescue ex
        handle_web_error("refreshing containers", env, ex)
      end
    end

    # Get system status
    get "/api/status" do |env|
      begin
        status = Mangrullo::StateManager.instance.status
        Mangrullo::JsonResponseHelper.send_success(env, status)
      rescue ex
        handle_web_error("getting status", env, ex)
      end
    end

    # Get all containers with update info
    get "/api/containers" do |env|
      begin
        containers = Mangrullo::ContainerStateHelper.all_containers
        result = containers.map do |data|
          {
            id:          data.container.id,
            name:        Mangrullo::ContainerNameUtils.normalize_name_string(data.container.name),
            image:       data.container.image,
            status:      data.container.status,
            created:     data.container.created,
            update_info: data.update_info,
          }
        end
        Mangrullo::JsonResponseHelper.send_success(env, result)
      rescue ex
        handle_web_error("getting containers", env, ex)
      end
    end

    # Job status endpoints
    get "/api/jobs/:job_id" do |env|
      begin
        job_id = env.params.url["job_id"]
        job_queue = Mangrullo::UpdateJobQueue.instance
        job = job_queue.get_job(job_id)

        if job
          Mangrullo::JsonResponseHelper.send_success(env, job.to_h)
        else
          Mangrullo::JsonResponseHelper.send_error(env, "Job not found", 404)
        end
      rescue ex
        handle_web_error("getting job status", env, ex)
      end
    end

    # Get jobs for a specific container
    get "/api/containers/:container_id/jobs" do |env|
      begin
        container_id = env.params.url["container_id"]
        job_queue = Mangrullo::UpdateJobQueue.instance
        jobs = job_queue.get_container_jobs(container_id)
        Mangrullo::JsonResponseHelper.send_success(env, jobs.map(&.to_h))
      rescue ex
        handle_web_error("getting container jobs", env, ex)
      end
    end

    # Health check
    get "/health" do
      "OK"
    end
  end

  private def setup_error_handlers
    # 404 handler
    error 404 do
      "Page not found"
    end

    # 500 handler
    error 500 do |env, exc|
      puts "Internal server error: #{exc.message}"
      Mangrullo::JsonResponseHelper.send_error(env, "Internal server error", 500, exc.message)
    end
  end

  private def major_update?(local_version : String?, remote_version : String?) : Bool
    Mangrullo::VersionUtils.major_update?(local_version, remote_version)
  end
end

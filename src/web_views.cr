require "kilt"
require "ecr"
require "./container_status"
require "./container_filter"
require "./display_formatter"

class WebViews
  def initialize(@update_manager : Mangrullo::UpdateManager)
  end

  def dashboard(env : HTTP::Server::Context, containers : Array(Mangrullo::ContainerInfo))
    env.response.content_type = "text/html"

    # Calculate statistics for the template
    # These variables are used by the ECR template (not a code error)
    # ameba:disable Lint/UselessAssign
    total_containers = containers.size
    # ameba:disable Lint/UselessAssign
    updates_available = containers.count do |container|
      container_state = Mangrullo::ContainerState.instance
      if data = container_state.container(container.id)
        data.update_info.try(&.[:needs_update]) == true
      else
        false
      end
    end

    # Render the ECR template directly from file
    ECR.render("src/templates/dashboard.ecr")
  end
end

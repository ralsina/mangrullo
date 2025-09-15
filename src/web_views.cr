require "ecr"
require "./container_status"
require "./container_filter"
require "./display_formatter"
require "./container_state_helper"

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
      Mangrullo::ContainerStateHelper.needs_update?(container.id)
    end

    # Render the ECR template directly from file
    ECR.render("src/templates/dashboard.ecr")
  end
end

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

  def container_details(env : HTTP::Server::Context, container : Mangrullo::ContainerInfo, update_info)
    env.response.content_type = "text/html"

    # Set variables needed by the template
    # ameba:disable Lint/UselessAssign
    name = container.name.lchop('/')
    # ameba:disable Lint/UselessAssign
    image = container.image
    # ameba:disable Lint/UselessAssign
    status = container.status
    # ameba:disable Lint/UselessAssign
    created = container.created.to_s("%Y-%m-%d %H:%M:%S")

    # Render the ECR template directly from file
    ECR.render("src/templates/container_details.ecr")
  end

  def bulk_operations(env : HTTP::Server::Context)
    env.response.content_type = "text/html"

    # For now, let's create a simple bulk operations page
    html = <<-HTML
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Mangrullo - Bulk Operations</title>
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@picocss/pico@1/css/pico.min.css">
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@picocss/pico@1/css/pico.colors.min.css">
    </head>
    <body>
        <nav class="container-fluid">
            <ul>
                <li><strong><a href="/">🐳 Mangrullo</a></strong></li>
            </ul>
        </nav>
        <main class="container">
            <h2>Bulk Operations</h2>
            <p>Use the dashboard to perform bulk operations on containers.</p>
            <a href="/" role="button" class="primary">Back to Dashboard</a>
        </main>
    </body>
    </html>
    HTML

    html
  end
end

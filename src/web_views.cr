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

    name = container.name.lchop('/')
    image = container.image
    status = container.status
    created = container.created.to_s("%Y-%m-%d %H:%M:%S")

    # For now, use embedded HTML since the template format doesn't match
    html = <<-HTML
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Mangrullo - #{name}</title>
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@picocss/pico@1/css/pico.min.css">
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@picocss/pico@1/css/pico.colors.min.css">
        <style>
            .status-up-to-date { color: #28a745; }
            .status-update-available { color: #ffc107; }
            .status-error { color: #dc3545; }
            .status-badge {
                padding: 0.25rem 0.5rem;
                border-radius: 0.25rem;
                font-size: 0.875rem;
                font-weight: bold;
            }
            .status-up-to-date .status-badge { background-color: #d4edda; color: #155724; }
            .status-update-available .status-badge { background-color: #fff3cd; color: #856404; }
            .status-error .status-badge { background-color: #f8d7da; color: #721c24; }
        </style>
    </head>
    <body>
        <nav class="container-fluid">
            <ul>
                <li><strong><a href="/">🐳 Mangrullo</a></strong></li>
            </ul>
        </nav>
        <main class="container">
            <h2>#{name}</h2>

            <div class="grid">
                <div>
                    <h3>Details</h3>
                    <table>
                        <tr>
                            <th>Image</th>
                            <td><code>#{image}</code></td>
                        </tr>
                        <tr>
                            <th>Status</th>
                            <td>#{status}</td>
                        </tr>
                        <tr>
                            <th>Created</th>
                            <td>#{created}</td>
                        </tr>
                        <tr>
                            <th>Container ID</th>
                            <td><code>#{container.id[0..11]}</code></td>
                        </tr>
                    </table>
                </div>

                <div>
                    <h3>Actions</h3>
                    <button onclick="checkUpdate('#{container.id}')" class="secondary">Check for Updates</button>
                    #{update_info && update_info[:needs_update] ? "<button onclick=\\\"showUpdateModal('#{container.id}')\\\" class=\\\"primary\\\">Update Container</button>" : ""}
                    <button onclick="restartContainer('#{container.id}')" class="contrast">Restart Container</button>
                    <a href="/" role="button" class="secondary">Back to Dashboard</a>
                </div>
            </div>

            #{update_info ? update_info_html(update_info) : "<p>No update information available</p>"}

            <h3>Logs</h3>
            <div>
                <button onclick="loadLogs()" class="secondary">Refresh Logs</button>
                <pre id="containerLogs" style="background: #f8f9fa; padding: 1rem; border-radius: 0.25rem; max-height: 400px; overflow-y: scroll;">Loading logs...</pre>
            </div>
        </main>

        <script>
            function checkUpdate(containerId) {
                fetch('/containers/' + containerId + '/check-update', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' }
                })
                .then(response => response.json())
                .then(data => {
                    alert('Update check completed');
                    location.reload();
                })
                .catch(error => {
                    alert('Error checking update');
                });
            }

            function showUpdateModal(containerId) {
                if (confirm('Are you sure you want to update this container?')) {
                    fetch('/containers/' + containerId + '/update', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ allow_major: false })
                    })
                    .then(response => response.json())
                    .then(data => {
                        alert('Container updated successfully!');
                        location.reload();
                    })
                    .catch(error => {
                        alert('Error updating container');
                    });
                }
            }

            function restartContainer(containerId) {
                if (confirm('Are you sure you want to restart this container?')) {
                    fetch('/containers/' + containerId + '/restart', {
                        method: 'POST'
                    })
                    .then(response => response.json())
                    .then(data => {
                        alert('Container restarted successfully!');
                        location.reload();
                    })
                    .catch(error => {
                        alert('Error restarting container');
                    });
                }
            }

            function loadLogs() {
                fetch('/containers/#{container.id}/logs?tail=100')
                    .then(response => response.text())
                    .then(data => {
                        document.getElementById('containerLogs').textContent = data;
                    })
                    .catch(error => {
                        document.getElementById('containerLogs').textContent = 'Error loading logs';
                    });
            }

            // Load logs when page loads
            loadLogs();
        </script>
    </body>
    </html>
    HTML

    html
  end

  private def update_info_html(update_info)
    html = <<-HTML
    <div>
        <h3>Update Information</h3>
        #{update_info[:needs_update] ?
            "<p><strong>Update Available!</strong></p>
             <p>#{update_info[:reason]}</p>
             #{update_info[:local_version] && update_info[:remote_version] ?
                 "<p>Current: #{update_info[:local_version]}<br>Available: #{update_info[:remote_version]}</p>" :
                 ""}" :
            "<p>Container is up to date</p>"}
        <p><small>Last checked: #{update_info[:last_checked]}</small></p>
    </div>
    HTML

    html
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

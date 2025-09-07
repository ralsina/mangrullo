require "kilt"
require "ecr"

class WebViews
  def dashboard(env : HTTP::Server::Context, containers : Array(Mangrullo::ContainerInfo))
    env.response.content_type = "text/html"

    # Calculate summary statistics
    total_containers = containers.size
    updates_available = containers.count { |container|
      begin
        docker_client = Mangrullo::DockerClient.new("/var/run/docker.sock")
        image_checker = Mangrullo::ImageChecker.new(docker_client)
        image_checker.needs_update?(container, false)
      rescue
        false
      end
    }

    # Create a simple template string rendering
    html = <<-HTML
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Mangrullo - Docker Container Updates</title>
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@picocss/pico@1/css/pico.min.css">
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@picocss/pico@1/css/pico.colors.min.css">
        <style>
            .status-up-to-date { color: #28a745; }
            .status-update-available { color: #ffc107; }
            .status-error { color: #dc3545; }
            .status-latest { color: #17a2b8; }
            .container-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); gap: 1rem; }
            .status-badge {
                padding: 0.25rem 0.5rem;
                border-radius: 0.25rem;
                font-size: 0.875rem;
                font-weight: bold;
            }
            .status-up-to-date .status-badge { background-color: #d4edda; color: #155724; }
            .status-update-available .status-badge { background-color: #fff3cd; color: #856404; }
            .status-error .status-badge { background-color: #f8d7da; color: #721c24; }
            .status-latest .status-badge { background-color: #d1ecf1; color: #0c5460; }
            .header-stats { display: flex; gap: 2rem; margin-bottom: 2rem; }
            .stat-card { background: var(--card-background-color); padding: 1rem; border-radius: 0.5rem; border: 1px solid var(--card-border-color); }
            @media (max-width: 768px) {
                .container-grid { grid-template-columns: 1fr; }
                .header-stats { flex-direction: column; gap: 1rem; }
            }
        </style>
    </head>
    <body>
        <nav class="container-fluid">
            <ul>
                <li><strong><a href="/">🐳 Mangrullo</a></strong></li>
            </ul>
            <ul>
                <li><a href="/" role="button" class="secondary">Dashboard</a></li>
                <li><a href="#" role="button" class="secondary" onclick="checkAllUpdates()">Check All Updates</a></li>
                <li><a href="#" role="button" class="primary" onclick="updateAllContainers()">Update All</a></li>
            </ul>
        </nav>

        <main class="container">
            <div class="header-stats">
                <div class="stat-card">
                    <h4>Total Containers</h4>
                    <p style="font-size: 2rem; margin: 0; font-weight: bold;">#{total_containers}</p>
                </div>
                <div class="stat-card">
                    <h4>Updates Available</h4>
                    <p style="font-size: 2rem; margin: 0; font-weight: bold; color: #ffc107;">#{updates_available}</p>
                </div>
                <div class="stat-card">
                    <h4>Last Updated</h4>
                    <p style="margin: 0;">#{Time.utc}</p>
                </div>
            </div>

            <h2>Running Containers</h2>

            <div class="container-grid">
    HTML

    containers.each do |container|
      status_class = "status-error"
      status_text = "Unknown"

      begin
        docker_client = Mangrullo::DockerClient.new("/var/run/docker.sock")
        image_checker = Mangrullo::ImageChecker.new(docker_client)
        needs_update = image_checker.needs_update?(container, false)

        if container.image.includes?("latest")
          status_class = "status-latest"
          status_text = "Latest Tag"
        elsif needs_update
          status_class = "status-update-available"
          status_text = "Update Available"
        else
          status_class = "status-up-to-date"
          status_text = "Up to Date"
        end
      rescue
        status_class = "status-error"
        status_text = "Error"
      end

      html += <<-HTML
                <div class="card status-#{status_class.split('-').last}" data-container-id="#{container.id}">
                    <article>
                        <header>
                            <h3>#{container.name}</h3>
                            <span class="status-badge">#{status_text}</span>
                        </header>
                        <p><strong>Image:</strong> #{container.image}</p>
                        <p><strong>Status:</strong> #{container.status}</p>
                        <p><strong>ID:</strong> <code>#{container.id[0..12]}</code></p>
                        <footer>
                            <button onclick="checkUpdate('#{container.id}')" class="secondary">Check Update</button>
                            <button onclick="showUpdateModal('#{container.id}')" class="primary">Update</button>
                            <a href="/containers/#{container.id}" class="button">Details</a>
                        </footer>
                    </article>
                </div>
      HTML
    end

    if containers.empty?
      html += <<-HTML
                <div class="card">
                    <article>
                        <h3>No Running Containers</h3>
                        <p>No Docker containers are currently running. Start some containers to see them here.</p>
                    </article>
                </div>
      HTML
    end

    html += <<-HTML
            </div>
        </main>

        <footer class="container">
            <hr>
            <p>Mangrullo v0.1.0 - Docker Container Update Automation</p>
        </footer>

        <script>
            function checkUpdate(containerId) {
                fetch('/containers/' + containerId + '/check-update', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' }
                })
                .then(response => response.json())
                .then(data => {
                    alert('Update check completed');
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

            function checkAllUpdates() {
                fetch('/api/updates')
                    .then(response => response.json())
                    .then(data => {
                        alert('Update check completed for all containers');
                    })
                    .catch(error => {
                        alert('Error checking updates');
                    });
            }

            function updateAllContainers() {
                if (confirm('Are you sure you want to update all containers?')) {
                    fetch('/api/updates', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ allow_major: false, dry_run: false })
                    })
                    .then(response => response.json())
                    .then(data => {
                        alert('Bulk update completed');
                        location.reload();
                    })
                    .catch(error => {
                        alert('Error in bulk update');
                    });
                }
            }
        </script>
    </body>
    </html>
    HTML

    html
  end

  def container_details(env : HTTP::Server::Context, container : Mangrullo::ContainerInfo, update_info)
    env.response.content_type = "text/html"

    update_status = "Unknown"
    status_class = "status-error"

    if update_info[:has_update]
      update_status = "Update Available"
      status_class = "status-update-available"
    else
      update_status = "Up to Date"
      status_class = "status-up-to-date"
    end

    html = <<-HTML
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Mangrullo - #{container.name}</title>
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
            <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 2rem;">
                <div>
                    <h2>#{container.name}</h2>
                    <p style="margin: 0; color: #666;">#{container.image}</p>
                </div>
                <div>
                    <a href="/" class="button secondary">← Back to Dashboard</a>
                </div>
            </div>

            <div style="display: grid; grid-template-columns: 2fr 1fr; gap: 2rem; margin-bottom: 2rem;">
                <div class="card">
                    <article>
                        <header>
                            <h3>Container Information</h3>
                        </header>
                        <p><strong>ID:</strong> <code>#{container.id}</code></p>
                        <p><strong>Name:</strong> #{container.name}</p>
                        <p><strong>Image:</strong> #{container.image}</p>
                        <p><strong>Image ID:</strong> <code>#{container.image_id[0..12]}</code></p>
                        <p><strong>Status:</strong> #{container.status}</p>
                        <p><strong>Created:</strong> #{container.created}</p>
                    </article>
                </div>

                <div class="card">
                    <article>
                        <header>
                            <h3>Update Status</h3>
                        </header>
                        <p><strong>Status:</strong> <span class="status-badge #{status_class}">#{update_status}</span></p>
                        #{update_info[:local_version] ? "<p><strong>Current Version:</strong> #{update_info[:local_version].to_s}</p>" : ""}
                        #{update_info[:remote_version] ? "<p><strong>Available Version:</strong> #{update_info[:remote_version].to_s}</p>" : ""}
                        <footer>
                            <button onclick="showUpdateModal('#{container.id}')" class="primary">Update Container</button>
                            <button onclick="checkUpdate('#{container.id}')" class="secondary">Check Again</button>
                        </footer>
                    </article>
                </div>
            </div>

            <div class="card">
                <article>
                    <header>
                        <h3>Actions</h3>
                    </header>
                    <div style="display: flex; gap: 1rem; flex-wrap: wrap;">
                        <button onclick="showUpdateModal('#{container.id}')" class="primary">🔄 Update Container</button>
                        <button onclick="restartContainer('#{container.id}')" class="secondary">🔄 Restart Container</button>
                        <button onclick="checkUpdate('#{container.id}')" class="secondary">🔍 Check for Updates</button>
                        <a href="/containers/#{container.id}/logs" class="button secondary">📋 View Logs</a>
                    </div>
                </article>
            </div>

            <div class="card" style="margin-top: 2rem;">
                <article>
                    <header>
                        <h3>Container Labels</h3>
                    </header>
                    #{container.labels.empty? ? "<p>No labels found for this container.</p>" : "<table><thead><tr><th>Label</th><th>Value</th></tr></thead><tbody>" +
                                                                                               container.labels.map { |k, v| "<tr><td><code>#{k}</code></td><td>#{v}</td></tr>" }.join("") +
                                                                                               "</tbody></table>"}
                </article>
            </div>
        </main>

        <script>
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

            function restartContainer(containerId) {
                if (confirm('Are you sure you want to restart this container?')) {
                    fetch('/containers/' + containerId + '/restart', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' }
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
        </script>
    </body>
    </html>
    HTML

    html
  end
end

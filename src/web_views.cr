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

    # Calculate summary statistics using UpdateManager for efficiency
    dashboard_stats = calculate_dashboard_stats(containers)

    # Always show table view
    render_dashboard_table(env, containers, dashboard_stats)
  end

  private def calculate_dashboard_stats(containers : Array(Mangrullo::ContainerInfo)) : NamedTuple(total_containers: Int32, updates_available: Int32)
    total_containers = containers.size

    # Get update info from cached state instead of making API calls
    container_state = Mangrullo::ContainerState.instance
    updates_available = containers.count { |container|
      if data = container_state.container(container.id)
        data.update_info.try(&.[:needs_update]) == true
      else
        false
      end
    }

    {total_containers: total_containers, updates_available: updates_available}
  end

  private def render_dashboard_table(env : HTTP::Server::Context, containers : Array(Mangrullo::ContainerInfo), stats : NamedTuple(total_containers: Int32, updates_available: Int32))
    # Sort containers alphabetically by name (without leading slash)
    sorted_containers = containers.sort_by(&.name.lchop('/'))

    # Prepare container data for table display
    container_data = sorted_containers.map do |container|
      # Get update status from cached state
      container_state = Mangrullo::ContainerState.instance
      data = container_state.container(container.id)
      needs_update = data ? (data.update_info.try(&.[:needs_update]) == true) : false
      reason = data ? data.update_info.try(&.[:reason]) : nil

      {
        container:    container,
        updated:      false,
        error:        nil,
        needs_update: needs_update,
        reason:       reason,
      }
    end

    # Generate HTML with embedded table
    html = <<-HTML
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Mangrullo - Container Status</title>
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@picocss/pico@1/css/pico.min.css">
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@picocss/pico@1/css/pico.colors.min.css">
        <link rel="stylesheet" href="/css/dashboard.css">
    </head>
    <body>
        <nav class="container-fluid">
            <ul>
                <li><strong><a href="/">🐳 Mangrullo</a></strong></li>
                <li><small style="color: #666;" id="autoRefreshStatus">Auto-refresh: ON</small></li>
            </ul>
            <ul>
                <li><a href="#" role="button" class="secondary" onclick="checkAllUpdates()">Check for Updates</a></li>
                <li><a href="#" role="button" class="primary" onclick="updateAllContainers()">Update All</a></li>
            </ul>
        </nav>
        <main class="container">
            <div class="header-stats">
                <div class="stat-card">
                    <h4>Total Containers</h4>
                    <p style="font-size: 2rem; margin: 0; font-weight: bold;">#{stats[:total_containers]}</p>
                </div>
                <div class="stat-card">
                    <h4>Updates Available</h4>
                    <p style="font-size: 2rem; margin: 0; font-weight: bold; color: #ffc107;">#{stats[:updates_available]}</p>
                </div>
            </div>

            <h2>Container Status</h2>
            <table class="container-table table-striped table-hover">
                <thead>
                    <tr>
                        <th>Container</th>
                        <th>Image</th>
                        <th>Status</th>
                        <th>Actions</th>
                    </tr>
                </thead>
                <tbody>
    HTML

    container_data.each do |data|
      container = data[:container]
      name = container.name.lchop('/')
      image = Mangrullo::DisplayFormatter.truncate_image_name(container.image, 50)
      status = Mangrullo::ContainerStatus.get_cli_status(container, data[:needs_update], data[:error])
      css_class = Mangrullo::ContainerStatus.get_css_class(container, data[:needs_update], data[:error])

      html += <<-HTML
                    <tr#{css_class ? " class=\"#{css_class}\"" : ""}>
                        <td>#{name}</td>
                        <td><code>#{image}</code></td>
                        <td>#{status}</td>
                        <td>
                            <div style="display: flex; gap: 0.5rem; align-items: center;">
                                #{data[:needs_update] ? "<button onclick=\"showUpdateModal('#{container.id}')\" class=\"primary\" style=\"padding: 0.25rem 0.75rem; font-size: 0.875rem; line-height: 1.25;\">Update</button>" : "<button onclick=\"checkUpdate('#{container.id}')\" class=\"secondary\" style=\"padding: 0.25rem 0.75rem; font-size: 0.875rem; line-height: 1.25;\">Check</button>"}
                            </div>
                        </td>
                    </tr>
      HTML
    end

    html += <<-HTML
                </tbody>
            </table>
        </main>

        <script src="/js/dashboard.js"></script>
        <script src="/js/auto-refresh.js"></script>
    </body>
    </html>
    HTML

    html
  end

  def container_details(env : HTTP::Server::Context, container : Mangrullo::ContainerInfo, update_info)
    env.response.content_type = "text/html"

    name = container.name.lchop('/')
    image = container.image
    status = container.status
    created = container.created.to_s("%Y-%m-%d %H:%M:%S")

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
                    #{update_info && update_info[:needs_update] ? "<button onclick=\"showUpdateModal('#{container.id}')\" class=\"primary\">Update Container</button>" : ""}
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

    html = <<-HTML
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Mangrullo - Bulk Operations</title>
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@picocss/pico@1/css/pico.min.css">
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@picocss/pico@1/css/pico.colors.min.css">
        <style>
            .operation-log {
                background: #f8f9fa;
                border: 1px solid #dee2e6;
                border-radius: 0.25rem;
                padding: 1rem;
                max-height: 300px;
                overflow-y: auto;
                font-family: monospace;
                font-size: 0.875rem;
            }
            .log-entry {
                margin: 0.25rem 0;
                padding: 0.25rem;
                border-radius: 0.125rem;
            }
            .log-entry.info { background: #e7f3ff; }
            .log-entry.success { background: #d4edda; }
            .log-entry.error { background: #f8d7da; }
            .hidden { display: none; }
            .progress-bar {
                height: 0.5rem;
                background: #e9ecef;
                border-radius: 0.25rem;
                overflow: hidden;
            }
            .progress-bar div {
                height: 100%;
                background: #007bff;
                transition: width 0.3s ease;
            }
            .progress-bar.success div {
                background: #28a745;
            }
            .progress-bar.error div {
                background: #dc3545;
            }
        </style>
    </head>
    <body>
        <nav class="container-fluid">
            <ul>
                <li><strong><a href="/">🐳 Mangrullo</a></strong></li>
            </ul>
        </nav>
        <main class="container">
            <h2>Bulk Operations</h2>

            <div class="grid">
                <div>
                    <h3>Check for Updates</h3>
                    <p>Check all containers for available updates without installing them.</p>
                    <button id="checkButton" onclick="startBulkCheck()" class="secondary">Check for Updates</button>

                    <div id="checkProgress" class="hidden">
                        <h4>Progress</h4>
                        <div class="progress-bar">
                            <div id="checkProgressBar" style="width: 0%"></div>
                        </div>
                        <p id="checkStatus">Initializing...</p>

                        <h4>Details</h4>
                        <div id="updateLog" class="operation-log"></div>
                    </div>
                </div>

                <div>
                    <h3>Update All Containers</h3>
                    <p>Update all containers that have available updates.</p>
                    <button onclick="updateAllContainers()" class="primary">Update All Containers</button>

                    <div id="updateProgress" class="hidden">
                        <h4>Progress</h4>
                        <div class="progress-bar">
                            <div id="updateProgressBar" style="width: 0%"></div>
                        </div>
                        <p id="updateStatus">Initializing...</p>

                        <h4>Details</h4>
                        <div id="updateLog" class="operation-log"></div>
                    </div>
                </div>
            </div>

            <div style="margin-top: 2rem;">
                <a href="/" role="button" class="secondary">Back to Dashboard</a>
            </div>
        </main>

        <script>
            function startBulkCheck() {
                const button = document.getElementById('checkButton');
                const progress = document.getElementById('checkProgress');
                const progressBar = document.getElementById('checkProgressBar');
                const status = document.getElementById('checkStatus');
                const log = document.getElementById('checkLog');

                button.disabled = true;
                progress.classList.remove('hidden');
                log.innerHTML = '';

                addLogEntry(log, 'Starting bulk update check...', 'info');

                fetch('/api/updates')
                    .then(response => response.json())
                    .then(data => {
                        // Simulate progress
                        simulateProgress(progressBar, () => {
                            addLogEntry(log, 'Update check completed successfully!', 'success');
                            status.textContent = 'Completed';
                            progressBar.classList.add('success');

                            // Show summary
                            const updatesAvailable = data.filter(c => c.needs_update).length;
                            addLogEntry(log, `Found ${updatesAvailable} containers needing updates`, 'info');

                            button.disabled = false;

                            // Refresh data and navigate back after a delay
                            setTimeout(() => {
                                window.location.href = '/';
                            }, 2000);
                        });
                    })
                    .catch(error => {
                        addLogEntry(log, 'Error: ' + error.message, 'error');
                        status.textContent = 'Error';
                        progressBar.classList.add('error');
                        button.disabled = false;
                    });
            }

            function simulateProgress(progressBar, callback) {
                let progress = 0;
                const interval = setInterval(() => {
                    progress += Math.random() * 30;
                    if (progress >= 100) {
                        progress = 100;
                        clearInterval(interval);
                        callback();
                    }
                    progressBar.style.width = progress + '%';
                }, 500);
            }

            function addLogEntry(logElement, message, type) {
                const entry = document.createElement('div');
                entry.className = `log-entry ${type}`;
                entry.textContent = `[${new Date().toLocaleTimeString()}] ${message}`;
                logElement.appendChild(entry);
                logElement.scrollTop = logElement.scrollHeight;
            }

            function updateAllContainers() {
                if (confirm('Are you sure you want to update all containers?')) {
                    window.location.href = '/api/updates';
                }
            }
        </script>
    </body>
    </html>
    HTML

    html
  end
end

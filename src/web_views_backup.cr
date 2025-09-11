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
      if data = container_state.get_container(container.id)
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
      data = container_state.get_container(container.id)
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
        <style>
            .header-stats { display: flex; gap: 2rem; margin-bottom: 2rem; }
            .stat-card { background: var(--card-background-color); padding: 1rem; border-radius: 0.5rem; border: 1px solid var(--card-border-color); }
            @media (max-width: 768px) {
                .header-stats { flex-direction: column; gap: 1rem; }
                table { font-size: 0.875rem; }
            }
        </style>
    </head>
    <body>
        <nav class="container-fluid">
            <ul>
                <li><strong><a href="/">🐳 Mangrullo</a></strong></li>
                <li><small style="color: #666;" id="autoRefreshStatus">Auto-refresh: ON</small></li>
            </ul>
            <ul>
                <li><a href="#" role="button" class="secondary" onclick="checkAllUpdates()">Check All Updates</a></li>
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
    HTML

    # Generate custom HTML table with action buttons
    html += <<-HTML
            <style>
                .container-table th:nth-child(3),
                .container-table td:nth-child(3) {
                    min-width: 150px;
                    width: 150px;
                }
                .container-table th:nth-child(1),
                .container-table td:nth-child(1) {
                    min-width: 120px;
                    width: 120px;
                }
                .container-table th:nth-child(4),
                .container-table td:nth-child(4) {
                    min-width: 160px;
                    width: 160px;
                }
            </style>
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
    HTML

    html += <<-HTML
        </main>

        <script>
            function checkUpdate(containerId) {
                fetch('/containers/' + containerId + '/check-update', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' }
                })
                .then(response => response.json())
                .then(data => {
                    showNotification('Update check completed', 'success');
                    // Refresh data instead of reloading page
                    refreshData();
                })
                .catch(error => {
                    showNotification('Error checking update', 'error');
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
                        showNotification('Container updated successfully!', 'success');
                        // Refresh data instead of reloading page
                        refreshData();
                    })
                    .catch(error => {
                        showNotification('Error updating container', 'error');
                    });
                }
            }

            function checkAllUpdates() {
                showNotification('Checking all containers for updates...', 'info');
                fetch('/api/updates')
                    .then(response => response.json())
                    .then(data => {
                        showNotification('Update check completed for all containers', 'success');
                        // Refresh data instead of reloading page
                        refreshData();
                    })
                    .catch(error => {
                        showNotification('Error checking updates', 'error');
                    });
            }

            function updateAllContainers() {
                if (confirm('Are you sure you want to update all containers?')) {
                    showNotification('Starting bulk update...', 'info');
                    fetch('/api/updates', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ allow_major: false, dry_run: false })
                    })
                    .then(response => response.json())
                    .then(data => {
                        showNotification('Bulk update completed', 'success');
                        // Refresh data instead of reloading page
                        refreshData();
                    })
                    .catch(error => {
                        showNotification('Error in bulk update', 'error');
                    });
                }
            }

            function showNotification(message, type) {
                const notification = document.createElement('div');
                notification.className = `notification ${type}`;
                notification.style.cssText = `
                    position: fixed;
                    top: 20px;
                    right: 20px;
                    padding: 1rem 1.5rem;
                    border-radius: 0.5rem;
                    color: white;
                    font-weight: bold;
                    z-index: 1000;
                    animation: slideIn 0.3s ease-out;
                `;

                switch(type) {
                    case 'success':
                        notification.style.backgroundColor = '#28a745';
                        break;
                    case 'error':
                        notification.style.backgroundColor = '#dc3545';
                        break;
                    case 'info':
                        notification.style.backgroundColor = '#17a2b8';
                        break;
                }

                notification.textContent = message;
                document.body.appendChild(notification);

                setTimeout(() => {
                    notification.remove();
                }, 3000);
            }
        </script>
        <style>
            @keyframes slideIn {
                from { transform: translateX(100%); opacity: 0; }
                to { transform: translateX(0); opacity: 1; }
            }
        </style>
    </body>
    </html>
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
            .operation-panel { margin-bottom: 2rem; padding: 1.5rem; border-radius: 0.5rem; background: var(--card-background-color); border: 1px solid var(--card-border-color); }
            .progress-bar { width: 100%; height: 20px; background: #e9ecef; border-radius: 0.25rem; overflow: hidden; margin: 1rem 0; }
            .progress-fill { height: 100%; background: #007bff; transition: width 0.3s ease; }
            .progress-fill.success { background: #28a745; }
            .progress-fill.error { background: #dc3545; }
            .operation-log { max-height: 300px; overflow-y: auto; background: #f8f9fa; padding: 1rem; border-radius: 0.25rem; font-family: monospace; font-size: 0.875rem; }
            .log-entry { margin-bottom: 0.5rem; padding-bottom: 0.5rem; border-bottom: 1px solid #dee2e6; }
            .log-entry:last-child { border-bottom: none; margin-bottom: 0; padding-bottom: 0; }
            .log-entry.success { color: #28a745; }
            .log-entry.error { color: #dc3545; }
            .log-entry.info { color: #17a2b8; }
            .hidden { display: none; }
        </style>
    </head>
    <body>
        <nav class="container-fluid">
            <ul>
                <li><strong><a href="/">🐳 Mangrullo</a></strong></li>
            </ul>
            <ul>
                <li><a href="/" role="button" class="secondary">← Back</a></li>
            </ul>
        </nav>

        <main class="container">
            <h2>Bulk Operations</h2>
            <p>Perform bulk operations on all containers with real-time progress tracking.</p>

            <!-- Check All Updates -->
            <div class="operation-panel">
                <h3>🔍 Check All Containers for Updates</h3>
                <p>This will check all running containers to see if updates are available.</p>
                <button onclick="startBulkCheck()" class="primary" id="checkButton">Check All Updates</button>

                <div id="checkProgress" class="hidden">
                    <h4>Progress</h4>
                    <div class="progress-bar">
                        <div id="checkProgressBar" class="progress-fill" style="width: 0%"></div>
                    </div>
                    <p id="checkStatus">Initializing...</p>

                    <h4>Details</h4>
                    <div id="checkLog" class="operation-log"></div>
                </div>
            </div>

            <!-- Update All Containers -->
            <div class="operation-panel">
                <h3>🔄 Update All Containers</h3>
                <p>This will update all containers that have available updates. Use with caution!</p>

                <div style="margin-bottom: 1rem;">
                    <label>
                        <input type="checkbox" id="allowMajor" name="allow_major">
                        Allow major version updates
                    </label>
                </div>

                <button onclick="startBulkUpdate()" class="primary" id="updateButton">Update All Containers</button>

                <div id="updateProgress" class="hidden">
                    <h4>Progress</h4>
                    <div class="progress-bar">
                        <div id="updateProgressBar" class="progress-fill" style="width: 0%"></div>
                    </div>
                    <p id="updateStatus">Initializing...</p>

                    <h4>Details</h4>
                    <div id="updateLog" class="operation-log"></div>
                </div>
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

            function startBulkUpdate() {
                const button = document.getElementById('updateButton');
                const progress = document.getElementById('updateProgress');
                const progressBar = document.getElementById('updateProgressBar');
                const status = document.getElementById('updateStatus');
                const log = document.getElementById('updateLog');
                const allowMajor = document.getElementById('allowMajor').checked;

                if (!confirm('Are you sure you want to update ALL containers? This action cannot be undone.')) {
                    return;
                }

                button.disabled = true;
                progress.classList.remove('hidden');
                log.innerHTML = '';

                addLogEntry(log, 'Starting bulk update operation...', 'info');
                addLogEntry(log, `Allow major updates: ${allowMajor}`, 'info');

                fetch('/api/updates', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ allow_major: allow_major, dry_run: false })
                })
                .then(response => response.json())
                .then(data => {
                    // Simulate progress
                    simulateProgress(progressBar, () => {
                        const updated = data.filter(r => r.updated).length;
                        const errors = data.filter(r => r.error).length;

                        addLogEntry(log, 'Bulk update completed!', 'success');
                        addLogEntry(log, `Updated: ${updated} containers`, 'info');
                        addLogEntry(log, `Errors: ${errors} containers`, errors > 0 ? 'error' : 'info');

                        if (errors > 0) {
                            data.filter(r => r.error).forEach(r => {
                                addLogEntry(log, `${r.container.name.replace(/^//, '')}: ${r.error}`, 'error');
                            });
                        }

                        status.textContent = 'Completed';
                        progressBar.classList.add('success');
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

            // Auto-refresh functionality
            alert('Auto-refresh script is loading!');
            console.log('Auto-refresh script loaded');
            let refreshInterval;

            function startAutoRefresh() {
                console.log('startAutoRefresh called');
                // Refresh every 30 seconds
                refreshInterval = setInterval(refreshData, 30000);
            }

            function stopAutoRefresh() {
                if (refreshInterval) {
                    clearInterval(refreshInterval);
                }
            }

            function refreshData() {
                console.log('refreshData called');
                // Show refreshing status
                const statusElement = document.getElementById('autoRefreshStatus');
                if (statusElement) {
                    statusElement.textContent = 'Auto-refresh: UPDATING...';
                    statusElement.style.color = '#007bff';
                }

                // Fetch updated container data
                Promise.all([
                    fetch('/api/containers').then(r => r.json()),
                    fetch('/api/status').then(r => r.json())
                ])
                .then(([containers, status]) => {
                    console.log('Got data:', { containers: containers.length, status: status });
                    updateHeaderStats(status);
                    updateContainerTable(containers);

                    // Reset status
                    if (statusElement) {
                        statusElement.textContent = 'Auto-refresh: ON';
                        statusElement.style.color = '#666';
                    }
                })
                .catch(error => {
                    console.error('Error refreshing data:', error);
                    // Show error status
                    if (statusElement) {
                        statusElement.textContent = 'Auto-refresh: ERROR';
                        statusElement.style.color = '#dc3545';
                    }
                });
            }

            function updateHeaderStats(status) {
                console.log('Updating header stats:', status);
                // Update the stats cards
                const totalElement = document.querySelector('.header-stats .stat-card:first-child p');
                const updatesElement = document.querySelector('.header-stats .stat-card:nth-child(2) p');
                console.log('Found elements:', { totalElement: !!totalElement, updatesElement: !!updatesElement });

                if (totalElement) {
                    totalElement.textContent = status.container_count;
                    console.log('Updated total count to:', status.container_count);
                }
                if (updatesElement) {
                    updatesElement.textContent = status.needing_update;
                    console.log('Updated updates count to:', status.needing_update);
                }
            }

            function updateContainerTable(containers) {
                const tbody = document.querySelector('.container-table tbody');
                if (!tbody) return;

                // Clear existing rows
                tbody.innerHTML = '';

                // Add updated rows
                containers.forEach(container => {
                    const row = createContainerRow(container);
                    tbody.appendChild(row);
                });
            }

            function createContainerRow(container) {
                const row = document.createElement('tr');
                if (container.status === 'running') {
                    row.classList.add('status-running');
                }

                const name = container.name.replace(/^//, '');
                const image = container.image.length > 50 ?
                    container.image.substring(0, 47) + '...' :
                    container.image;

                const needsUpdate = container.update_info && container.update_info.needs_update;
                const status = needsUpdate ? 'Update available' : 'Up to date';

                row.innerHTML = `
                    <td>${name}</td>
                    <td><code>${image}</code></td>
                    <td>${status}</td>
                    <td>
                        <div style="display: flex; gap: 0.5rem; align-items: center;">
                            ${needsUpdate ?
                                `<button onclick="showUpdateModal('${container.id}')" class="primary" style="padding: 0.25rem 0.75rem; font-size: 0.875rem; line-height: 1.25;">Update</button>` :
                                `<button onclick="checkUpdate('${container.id}')" class="secondary" style="padding: 0.25rem 0.75rem; font-size: 0.875rem; line-height: 1.25;">Check</button>`
                            }
                        </div>
                    </td>
                `;

                return row;
            }

            // Start auto-refresh when page loads
            console.log('Setting up auto-refresh');
            try {
                if (document.readyState === 'loading') {
                    console.log('Document still loading, adding DOMContentLoaded listener');
                    document.addEventListener('DOMContentLoaded', function() {
                        console.log('DOMContentLoaded fired, starting auto-refresh');
                        startAutoRefresh();
                    });
                } else {
                    console.log('Document already loaded, starting auto-refresh immediately');
                    startAutoRefresh();
                }
            } catch (e) {
                console.error('Error setting up auto-refresh:', e);
            }
        </script>
    </body>
    </html>
    HTML

    html
  end

  def container_details(env : HTTP::Server::Context, container : Mangrullo::ContainerInfo, update_info)
    env.response.content_type = "text/html"

    # Use ContainerStatus module
    needs_update = update_info ? update_info[:needs_update] : false
    status = Mangrullo::ContainerStatus.get_status(container, needs_update)
    update_status = status.text
    status_class = status.css_class || "status-unknown"

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
                    <h2>#{container.name.lchop('/')}</h2>
                    <p style="margin: 0; color: #666;">#{container.image}</p>
                </div>
                <div>
                    <a href="/" class="button secondary">← Back</a>
                </div>
            </div>

            <div style="display: grid; grid-template-columns: 2fr 1fr; gap: 2rem; margin-bottom: 2rem;">
                <div class="card">
                    <article>
                        <header>
                            <h3>Container Information</h3>
                        </header>
                        <p><strong>ID:</strong> <code>#{container.id}</code></p>
                        <p><strong>Name:</strong> #{container.name.lchop('/')}</p>
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
                        #{update_info && update_info[:local_version] ? "<p><strong>Current Version:</strong> #{update_info[:local_version]}</p>" : ""}
                        #{update_info && update_info[:remote_version] ? "<p><strong>Available Version:</strong> #{update_info[:remote_version]}</p>" : ""}
                        <footer>
                            #{needs_update ? "<button onclick=\"showUpdateModal('#{container.id}')\" class=\"primary\">Update Container</button>" : "<button onclick=\"checkUpdate('#{container.id}')\" class=\"secondary\">Check Again</button>"}
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
                        #{needs_update ? "<button onclick=\"showUpdateModal('#{container.id}')\" class=\"primary\">Update Container</button>" : ""}
                        <button onclick="restartContainer('#{container.id}')" class="secondary">Restart Container</button>
                        #{!needs_update ? "<button onclick=\"checkUpdate('#{container.id}')\" class=\"secondary\">Check for Updates</button>" : ""}
                        <a href="/containers/#{container.id}/logs" class="button secondary">View Logs</a>
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
                        showNotification('Container updated successfully!');
                        location.reload();
                    })
                    .catch(error => {
                        showNotification('Error updating container');
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
                    showNotification('Update check completed');
                    // For container details page, we still reload to go back to the main view
                    location.reload();
                })
                .catch(error => {
                    showNotification('Error checking update');
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
                        showNotification('Container restarted successfully!');
                        // For container details page, we still reload to refresh status
                        location.reload();
                    })
                    .catch(error => {
                        showNotification('Error restarting container');
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

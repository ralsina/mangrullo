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

    # Check view preference (default to cards)
    view_mode = env.params.query["view"]? || "cards"

    # Generate HTML based on view mode
    case view_mode
    when "table"
      render_dashboard_table(env, containers, dashboard_stats)
    else
      render_dashboard_html(env, containers, dashboard_stats)
    end
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

  private def render_dashboard_html(env : HTTP::Server::Context, containers : Array(Mangrullo::ContainerInfo), stats : NamedTuple(total_containers: Int32, updates_available: Int32))
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
                <li><a href="?view=table" role="button" class="#{env.params.query["view"]? == "table" ? "primary" : "secondary"}">Table View</a></li>
                <li><a href="?view=cards" role="button" class="#{env.params.query["view"]? != "table" ? "primary" : "secondary"}">Card View</a></li>
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
                <div class="stat-card">
                    <h4>Last Updated</h4>
                    <p style="margin: 0;">#{Time.utc}</p>
                </div>
            </div>

            <h2>Running Containers</h2>

            <div class="container-grid">
    HTML

    # Sort containers alphabetically by name (without leading slash)
    sorted_containers = containers.sort_by(&.name.lchop('/'))

    sorted_containers.each do |container|
      # Get update status from cached state
      container_state = Mangrullo::ContainerState.instance
      data = container_state.get_container(container.id)
      needs_update = data ? (data.update_info.try(&.[:needs_update]) == true) : false

      status = Mangrullo::ContainerStatus.get_status(container, needs_update)
      status_class = status.css_class || "status-unknown"
      status_text = status.text

      html += <<-HTML
                <div class="card status-#{status_class.split('-').last}" data-container-id="#{container.id}">
                    <article>
                        <header>
                            <h3>#{container.name.lchop('/')}</h3>
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

    if sorted_containers.empty?
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
                    showNotification('Update check completed', 'success');
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
                        showNotification('Container updated successfully!');
                        location.reload();
                    })
                    .catch(error => {
                        showNotification('Error updating container');
                    });
                }
            }

            function checkAllUpdates() {
                fetch('/api/updates')
                    .then(response => response.json())
                    .then(data => {
                        showNotification('Update check completed for all containers');
                    })
                    .catch(error => {
                        showNotification('Error checking updates');
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
                        showNotification('Bulk update completed', 'success');
                        location.reload();
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
        <title>Mangrullo - Docker Container Updates</title>
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@picocss/pico@1/css/pico.min.css">
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@picocss/pico@1/css/pico.colors.min.css">
        <style>
            .header-stats { display: flex; gap: 2rem; margin-bottom: 2rem; }
            .stat-card { background: var(--card-background-color); padding: 1rem; border-radius: 0.5rem; border: 1px solid var(--card-border-color); }
            .view-toggle { margin-bottom: 1rem; }
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
            </ul>
            <ul>
                <li><a href="/" role="button" class="secondary">Dashboard</a></li>
                <li><a href="?view=table" role="button" class="#{env.params.query["view"]? == "table" ? "primary" : "secondary"}">Table View</a></li>
                <li><a href="?view=cards" role="button" class="#{env.params.query["view"]? != "table" ? "primary" : "secondary"}">Card View</a></li>
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
                <div class="stat-card">
                    <h4>Last Updated</h4>
                    <p style="margin: 0;">#{Time.utc}</p>
                </div>
            </div>

            <div class="view-toggle">
                <h2>Container Status (Table View)</h2>
            </div>
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
                                <button onclick="checkUpdate('#{container.id}')" class="secondary" style="padding: 0.25rem 0.75rem; font-size: 0.875rem; line-height: 1.25;">Check</button>
                                #{data[:needs_update] ? "<button onclick=\"updateContainer('#{container.id}')\" class=\"primary\" style=\"padding: 0.25rem 0.75rem; font-size: 0.875rem; line-height: 1.25;\">📥 Update</button>" : ""}
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

            <div style="margin-top: 2rem;">
                <h3>Quick Actions</h3>
                <div style="display: flex; gap: 1rem; flex-wrap: wrap;">
                    <button onclick="checkAllUpdates()" class="secondary">🔍 Check All Updates</button>
                    <button onclick="updateAllContainers()" class="primary">🔄 Update All Containers</button>
                    <a href="/api/dry-run" class="button secondary">📋 Dry Run Report</a>
                </div>
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
                    showNotification('Update check completed', 'success');
                    location.reload();
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
                        location.reload();
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
                        location.reload();
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
                        location.reload();
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

  def dry_run_results(env : HTTP::Server::Context, results : Array(NamedTuple(container: Mangrullo::ContainerInfo, needs_update: Bool, reason: String?)), allow_major : Bool)
    env.response.content_type = "text/html"

    # Calculate statistics
    total = results.size
    needing_update = results.count { |result| result[:needs_update] }
    up_to_date = total - needing_update

    # Generate HTML
    html = <<-HTML
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Mangrullo - Dry Run Results</title>
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@picocss/pico@1/css/pico.min.css">
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@picocss/pico@1/css/pico.colors.min.css">
        <style>
            .summary-stats { display: flex; gap: 2rem; margin-bottom: 2rem; }
            .stat-card { background: var(--card-background-color); padding: 1.5rem; border-radius: 0.5rem; border: 1px solid var(--card-border-color); text-align: center; }
            .stat-number { font-size: 2.5rem; font-weight: bold; margin: 0; }
            .stat-label { color: #666; margin: 0.5rem 0 0 0; }
            .needs-update { color: #ffc107; }
            .up-to-date { color: #28a745; }
            .update-reason { font-style: italic; color: #666; }
            .container-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(350px, 1fr)); gap: 1rem; }
            .container-card.update-needed { border-left: 4px solid #ffc107; }
            .container-card.up-to-date { border-left: 4px solid #28a745; }
            @media (max-width: 768px) {
                .summary-stats { flex-direction: column; }
                .container-grid { grid-template-columns: 1fr; }
            }
        </style>
    </head>
    <body>
        <nav class="container-fluid">
            <ul>
                <li><strong><a href="/">🐳 Mangrullo</a></strong></li>
            </ul>
            <ul>
                <li><a href="/" role="button" class="secondary">← Back to Dashboard</a></li>
                <li><a href="?allow_major=true" role="button" class="#{allow_major ? "primary" : "secondary"}">Include Major Updates</a></li>
                <li><a href="?allow_major=false" role="button" class="#{!allow_major ? "primary" : "secondary"}">Exclude Major Updates</a></li>
            </ul>
        </nav>

        <main class="container">
            <div class="summary-stats">
                <div class="stat-card">
                    <p class="stat-number">#{total}</p>
                    <p class="stat-label">Total Containers</p>
                </div>
                <div class="stat-card">
                    <p class="stat-number needs-update">#{needing_update}</p>
                    <p class="stat-label">Need Updates</p>
                </div>
                <div class="stat-card">
                    <p class="stat-number up-to-date">#{up_to_date}</p>
                    <p class="stat-label">Up to Date</p>
                </div>
            </div>

            <h2>Dry Run Results #{allow_major ? "(Including Major Updates)" : ""}</h2>
            <p>This report shows which containers would be updated if you ran the update operation now.</p>

            <div class="container-grid">
    HTML

    # Display each container
    results.each do |result|
      container = result[:container]
      needs_update = result[:needs_update]
      reason = result[:reason]

      card_class = needs_update ? "update-needed" : "up-to-date"
      status_icon = needs_update ? "⚠️" : "✅"
      status_text = needs_update ? "Update Needed" : "Up to Date"

      html += <<-HTML
                <div class="card container-card #{card_class}">
                    <article>
                        <header>
                            <h3>#{container.name.lchop('/')}</h3>
                            <span>#{status_icon} #{status_text}</span>
                        </header>
                        <p><strong>Image:</strong> <code>#{container.image}</code></p>
                        <p><strong>Status:</strong> #{container.status}</p>
                        #{needs_update && reason ? "<p class=\"update-reason\"><strong>Reason:</strong> #{reason}</p>" : ""}
                        <footer>
                            <a href="/containers/#{container.id}" class="button">View Details</a>
                            #{needs_update ? "<button onclick=\"updateContainer('#{container.id}')\" class=\"primary\">Update Container</button>" : ""}
                        </footer>
                    </article>
                </div>
      HTML
    end

    if results.empty?
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

            <div style="margin-top: 3rem; text-align: center;">
                <h3>Next Steps</h3>
                <div style="display: flex; gap: 1rem; justify-content: center; flex-wrap: wrap; margin-top: 1rem;">
                    <button onclick="updateAllContainers()" class="primary">🔄 Update All Containers</button>
                    <a href="/" class="button secondary">← Back to Dashboard</a>
                </div>
            </div>
        </main>

        <script>
            function updateContainer(containerId) {
                if (confirm('Are you sure you want to update this container?')) {
                    showNotification('Updating container...', 'info');
                    fetch('/containers/' + containerId + '/update', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ allow_major: #{allow_major} })
                    })
                    .then(response => response.json())
                    .then(data => {
                        if (data.error) {
                            showNotification('Error: ' + data.error, 'error');
                        } else {
                            showNotification('Container updated successfully!', 'success');
                            setTimeout(() => location.reload(), 1500);
                        }
                    })
                    .catch(error => {
                        showNotification('Error updating container', 'error');
                    });
                }
            }

            function updateAllContainers() {
                if (confirm('Are you sure you want to update all containers that need updates?')) {
                    showNotification('Starting bulk update...', 'info');
                    fetch('/api/updates', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ allow_major: #{allow_major}, dry_run: false })
                    })
                    .then(response => response.json())
                    .then(data => {
                        showNotification('Bulk update completed', 'success');
                        location.href = '/';
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
                <li><a href="/" role="button" class="secondary">← Back to Dashboard</a></li>
                <li><a href="/api/dry-run" role="button" class="secondary">📋 Dry Run Report</a></li>
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

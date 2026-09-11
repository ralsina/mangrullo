let currentContainerId = null;

        function applyTheme(theme) {
            document.documentElement.setAttribute('data-theme', theme);
            const themeToggleIcon = document.getElementById('themeToggleIcon');
            if (themeToggleIcon) {
                themeToggleIcon.textContent = theme === 'dark' ? 'light_mode' : 'dark_mode';
            }
        }

        function toggleTheme() {
            const current = document.documentElement.getAttribute('data-theme') === 'light' ? 'light' : 'dark';
            const next = current === 'dark' ? 'light' : 'dark';
            applyTheme(next);
            try {
                localStorage.setItem('mangrullo-theme', next);
            } catch {
                // localStorage unavailable; theme resets on reload
            }
        }

        // Keep the toggle icon in sync with the theme applied before paint
        document.addEventListener('DOMContentLoaded', function () {
            applyTheme(document.documentElement.getAttribute('data-theme') === 'light' ? 'light' : 'dark');
        });

        function showUpdateModal(containerId) {
            currentContainerId = containerId;
            document.getElementById('updateModal').showModal();
        }

        function closeModal() {
            document.getElementById('updateModal').close();
            currentContainerId = null;
        }

        function showBulkUpdateModal() {
            document.getElementById('bulkUpdateModal').showModal();
        }

        function closeBulkModal() {
            document.getElementById('bulkUpdateModal').close();
        }

        function showDryRunResultsModal(results) {
            const modal = document.getElementById('dryRunResultsModal');
            const resultsDiv = document.getElementById('dryRunResults');

            // Count results
            const needingUpdate = results.filter(r => r.needs_update);
            const upToDate = results.filter(r => !r.needs_update);

            // Generate summary
            const summaryHtml = `
                <div class="results-summary">
                    <h4>Summary</h4>
                    <p><strong>Total containers:</strong> ${results.length}</p>
                    <p><strong>Would be updated:</strong> ${needingUpdate.length}</p>
                    <p><strong>Already up-to-date:</strong> ${upToDate.length}</p>
                </div>
            `;

            // Generate table
            let tableHtml = `
                <table class="results-table">
                    <thead>
                        <tr>
                            <th>Container</th>
                            <th>Image</th>
                            <th>Status</th>
                            <th>Reason</th>
                        </tr>
                    </thead>
                    <tbody>
            `;

            results.forEach(result => {
                const containerName = result.container.name.startsWith('/') ?
                    result.container.name.substring(1) : result.container.name;
                const fullImage = result.container.image;
                const displayImage = fullImage.length > 40 ? fullImage.substring(0, 37) + '...' : fullImage;
                const statusClass = result.needs_update ? 'status-needs-update' : 'status-up-to-date-table';
                const statusText = result.needs_update ? 'Needs Update' : 'Up to Date';
                const reason = result.reason || (result.needs_update ? 'Update available' : 'Already current');

                tableHtml += `
                    <tr>
                        <td title="${containerName}">${containerName}</td>
                        <td class="image-cell" title="${fullImage}"><code>${displayImage}</code></td>
                        <td class="${statusClass}">${statusText}</td>
                        <td title="${reason}">${reason}</td>
                    </tr>
                `;
            });

            tableHtml += `
                    </tbody>
                </table>
            `;

            resultsDiv.innerHTML = summaryHtml + tableHtml;
            modal.showModal();
        }

        function closeDryRunResultsModal() {
            document.getElementById('dryRunResultsModal').close();
        }

        async function checkUpdate(containerId) {
            const row = findContainerRow(containerId);
            if (!row) return;

            const button = row.querySelector('button[onclick*="checkUpdate"]');
            const originalText = button.textContent;
            const originalOnclick = button.getAttribute('onclick');

            button.textContent = 'Checking...';
            button.disabled = true;
            button.removeAttribute('onclick'); // Remove onclick to prevent accidental clicks

            try {
                const response = await fetch(`/containers/${containerId}/check-update`, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                    }
                });

                const data = await response.json();

                if (data.has_update) {
                    updateContainerStatus(containerId, 'update-available', data.local_version, data.remote_version);
                } else {
                    updateContainerStatus(containerId, 'up-to-date', data.local_version, data.remote_version);
                }

                showNotification('Update check completed', 'success');
            } catch (error) {
                console.error('Error checking update:', error);
                updateContainerStatus(containerId, 'error', null, null);
                showNotification('Failed to check update', 'error');
            } finally {
                button.textContent = originalText;
                button.disabled = false;
                button.setAttribute('onclick', originalOnclick); // Restore onclick
            }
        }

        async function confirmUpdate() {
            if (!currentContainerId) {
                console.error('No container ID set for update');
                showNotification('Error: No container selected', 'error');
                return;
            }

            const allowMajor = document.getElementById('allowMajor').checked;
            const row = findContainerRow(currentContainerId);
            if (!row) return;

            const button = row.querySelector('button[onclick*="showUpdateModal"]');
            const originalText = button.textContent;
            const originalOnclick = button.getAttribute('onclick');

            button.textContent = 'Updating...';
            button.disabled = true;
            button.removeAttribute('onclick'); // Remove onclick to prevent accidental clicks

            // Close modal AFTER saving the ID
            const savedContainerId = currentContainerId;
            closeModal();

            // Use the saved ID since closeModal() nullifies it
            try {
                const response = await fetch(`/containers/${savedContainerId}/update`, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                    },
                    body: JSON.stringify({ allow_major: allowMajor })
                });

                const data = await response.json();

                if (data.job_id) {
                    // Update is queued
                    showNotification('Update job queued successfully', 'info');
                    // Start polling for job status
                    pollJobStatus(savedContainerId, data.job_id, button, originalText);
                } else if (data.updated) {
                    // Legacy response for backwards compatibility
                    updateContainerStatus(savedContainerId, 'up-to-date', null, null);
                    showNotification('Container updated successfully!', 'success');
                    setTimeout(() => location.reload(), 1500);
                } else {
                    showNotification(`Update failed: ${data.error}`, 'error');
                    updateContainerStatus(savedContainerId, 'error', null, null);
                    button.textContent = originalText;
                    button.disabled = false;
                    button.setAttribute('onclick', originalOnclick); // Restore onclick
                }
            } catch (error) {
                console.error('Error updating container:', error);
                showNotification('Update failed', 'error');
                updateContainerStatus(savedContainerId, 'error', null, null);
                button.textContent = originalText;
                button.disabled = false;
                button.setAttribute('onclick', originalOnclick); // Restore onclick
            }
        }

        // Poll for job status
        async function pollJobStatus(containerId, jobId, button, originalButtonText) {
            const maxPolls = 60; // Poll for up to 5 minutes (60 * 5 seconds)
            let pollCount = 0;
            const originalOnclick = `showUpdateModal('${containerId}')`;

            const pollInterval = setInterval(async () => {
                try {
                    const response = await fetch(`/api/jobs/${jobId}`);

                    // Handle 404 - the job expired or was lost (e.g. server
                    // restart). The outcome is unknown, so fail safe: restore
                    // the button and refresh the real state from the server.
                    if (response.status === 404) {
                        clearInterval(pollInterval);
                        button.textContent = originalButtonText;
                        button.disabled = false;
                        button.setAttribute('onclick', originalOnclick);
                        showNotification('Update job status lost or expired - refresh to see the actual state', 'warning');
                        refreshData();
                        return;
                    }

                    const job = await response.json();

                    // Update button text with progress
                    switch (job.status) {
                        case 'pending':
                            button.textContent = 'Queued...';
                            break;
                        case 'running':
                            button.textContent = 'Updating...';
                            break;
                        case 'completed':
                            clearInterval(pollInterval);

                            if (job.result && job.result.updated) {
                                // Update was successful - update status first, then clean up button
                                updateContainerStatus(containerId, 'up-to-date', null, null);
                                showNotification('Container updated successfully!', 'success');

                                // Check if container was recreated
                                if (job.result.new_container_id && job.result.new_container_id !== containerId) {
                                    // Container has a new ID, reload the page
                                    setTimeout(() => location.reload(), 1500);
                                } else {
                                    // Same container ID, just refresh the data
                                    refreshData();
                                }
                            } else {
                                // Update wasn't successful - restore the update button
                                button.textContent = originalButtonText;
                                button.disabled = false;
                                button.setAttribute('onclick', originalOnclick);
                                showNotification('Update completed but may not have been successful', 'warning');
                            }
                            break;
                        case 'failed':
                            clearInterval(pollInterval);
                            button.textContent = originalButtonText;
                            button.disabled = false;
                            button.setAttribute('onclick', originalOnclick);
                            updateContainerStatus(containerId, 'error', null, null);
                            showNotification(`Update failed: ${job.error || 'Unknown error'}`, 'error');
                            break;
                    }

                    pollCount++;
                    if (pollCount >= maxPolls) {
                        clearInterval(pollInterval);
                        button.textContent = originalButtonText;
                        button.disabled = false;
                        button.setAttribute('onclick', originalOnclick);
                        showNotification('Update timed out', 'error');
                    }
                } catch (error) {
                    console.error('Error polling job status:', error);
                    clearInterval(pollInterval);
                    button.textContent = originalButtonText;
                    button.disabled = false;
                    button.setAttribute('onclick', originalOnclick);

                    // If it's a JSON parsing error near the end of polling the
                    // server may have restarted mid-update: the outcome is
                    // unknown, so restore the button and refresh the state.
                    if (error.name === 'SyntaxError' && pollCount > maxPolls * 0.8) {
                        button.textContent = originalButtonText;
                        button.disabled = false;
                        button.setAttribute('onclick', originalOnclick);
                        showNotification('Update finished but status is unclear - refreshing current state', 'warning');
                        refreshData();
                    } else {
                        // Only restore button on actual errors, not assumed success
                        showNotification('Error checking update status', 'error');
                    }
                }
            }, 5000); // Poll every 5 seconds
        }

        async function checkAllUpdates() {
            try {
                // First, trigger a fresh check for all containers
                const refreshResponse = await fetch('/api/refresh', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                    }
                });

                const refreshData = await refreshResponse.json();

                if (!refreshData.success) {
                    showNotification(refreshData.message || 'Refresh already in progress', 'warning');
                    return;
                }

                // Show single notification after successful refresh initiation
                showNotification('Checking all containers for updates...', 'info');

                // Poll every 2 seconds, up to 10 times (20 seconds total)
                let attempts = 0;
                const maxAttempts = 10;

                const pollUpdates = async () => {
                    try {
                        // Fetch both containers and status
                        const [containersResponse, statusResponse] = await Promise.all([
                            fetch('/api/containers'),
                            fetch('/api/status')
                        ]);

                        const containers = await containersResponse.json();
                        const status = await statusResponse.json();

                        // Update the UI with fresh data
                        updateHeaderStats(containers);
                        updateContainerTable(containers);

                        attempts++;

                        // Check if updates are still in progress
                        if (status.update_in_progress && attempts < maxAttempts) {
                            // Still updating, continue polling
                            setTimeout(pollUpdates, 2000);
                        } else if (status.update_in_progress && attempts >= maxAttempts) {
                            // Timeout but still updating
                            showNotification('Update check is still in progress...', 'warning');
                        } else {
                            // Updates actually completed
                            showNotification('Update check completed!', 'success');
                        }
                    } catch (error) {
                        console.error('Error polling updates:', error);
                        if (attempts < maxAttempts) {
                            setTimeout(pollUpdates, 2000);
                        } else {
                            showNotification('Failed to check updates', 'error');
                        }
                    }
                };

                // Start polling after a short delay
                setTimeout(pollUpdates, 1000);

            } catch (error) {
                console.error('Error checking all updates:', error);
                showNotification('Failed to check updates', 'error');
            }
        }

        function updateAllContainers() {
            showBulkUpdateModal();
        }

        async function confirmBulkUpdate() {
            const allowMajor = document.getElementById('bulkAllowMajor').checked;
            const dryRun = document.getElementById('dryRun').checked;

            // Disable the "Update All" button in navbar to prevent double-clicks
            const updateAllBtn = document.querySelector('a[onclick="updateAllContainers()"]');
            const originalUpdateAllText = updateAllBtn.textContent;
            updateAllBtn.textContent = dryRun ? 'Dry Running...' : 'Updating All...';
            updateAllBtn.classList.add('btn-busy');

            closeBulkModal();

            try {
                // Show notification about the operation starting
                showNotification(dryRun ? 'Starting dry run...' : 'Queuing container updates...', 'info');

                // Dry runs inspect every container and can take a while
                const controller = new AbortController();
                const timeoutId = setTimeout(() => controller.abort(), 300000); // 5 minutes

                const response = await fetch('/api/updates', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                    },
                    body: JSON.stringify({ allow_major: allowMajor, dry_run: dryRun }),
                    signal: controller.signal
                });

                clearTimeout(timeoutId);

                const data = await response.json();

                if (dryRun) {
                    if (Array.isArray(data)) {
                        // Dry run results: {container, needs_update, reason}
                        showDryRunResultsModal(data);
                        showNotification('Dry run completed - see detailed results in modal', 'success');
                        refreshData();
                    } else {
                        showNotification('Unexpected dry run response', 'error');
                    }
                } else if (data.queued && Array.isArray(data.job_ids)) {
                    // Updates were queued (202): poll the jobs instead of
                    // holding an HTTP request open for the whole bulk run
                    showNotification(`${data.count} update${data.count === 1 ? '' : 's'} queued`, 'info');
                    await pollBulkJobs(data.job_ids);
                } else {
                    showNotification('Unexpected bulk update response', 'error');
                }
            } catch (error) {
                console.error('Error in bulk update:', error);

                if (error.name === 'AbortError') {
                    showNotification('Bulk update timed out - some containers may have been updated. Please refresh to see current status.', 'warning');
                    // Force refresh after timeout
                    setTimeout(() => location.reload(), 2000);
                } else {
                    showNotification('Bulk update failed', 'error');
                }
            } finally {
                // Always restore the "Update All" button
                updateAllBtn.textContent = originalUpdateAllText;
                updateAllBtn.classList.remove('btn-busy');
            }
        }

        // Poll queued bulk-update jobs until every one settles, then reload.
        // A job that can no longer be found (server restart) is counted as
        // unknown and excluded from the summary.
        async function pollBulkJobs(jobIds) {
            const outstanding = new Set(jobIds);
            let failedCount = 0;
            const pollInterval = 5000;
            const maxPolls = 90; // ~7.5 minutes
            let polls = 0;

            while (outstanding.size > 0 && polls < maxPolls) {
                await new Promise(resolve => setTimeout(resolve, pollInterval));
                polls++;

                for (const jobId of [...outstanding]) {
                    try {
                        const response = await fetch(`/api/jobs/${jobId}`);
                        if (!response.ok) {
                            outstanding.delete(jobId);
                            continue;
                        }
                        const job = await response.json();
                        if (job.status === 'completed') {
                            outstanding.delete(jobId);
                        } else if (job.status === 'failed') {
                            failedCount++;
                            outstanding.delete(jobId);
                            showNotification(`Update failed for ${job.container_name}`, 'error');
                        }
                    } catch (error) {
                        console.error('Error polling bulk update job:', error);
                    }
                }
            }

            const succeeded = jobIds.length - failedCount - outstanding.size;
            const summary = outstanding.size > 0
                ? `Bulk update timed out tracking ${succeeded} succeeded, ${failedCount} failed, ${outstanding.size} unknown`
                : `Bulk update finished: ${succeeded} succeeded, ${failedCount} failed`;
            showNotification(summary, failedCount > 0 || outstanding.size > 0 ? 'warning' : 'success');
            setTimeout(() => location.reload(), 1500);
        }

        function findContainerRow(containerId) {
            // Find the row that contains a button with this containerId
            const buttons = document.querySelectorAll(`button[onclick*="${containerId}"]`);
            for (let button of buttons) {
                let row = button.closest('tr');
                if (row) return row;
            }
            return null;
        }

        function updateContainerStatus(containerId, status, _localVersion, _remoteVersion) {
            const row = findContainerRow(containerId);
            if (!row) return;

            // Remove all status classes
            row.classList.remove('status-up-to-date', 'status-update-available', 'status-error', 'status-latest');
            row.classList.add(`status-${status}`);

            // Update actions cell to show/hide update button
            const actionsCell = row.cells[2];
            if (actionsCell && status === 'update-available') {
                // Check if update button already exists
                let updateBtn = actionsCell.querySelector('button[onclick*="showUpdateModal"]');
                if (!updateBtn) {
                    const checkBtn = actionsCell.querySelector('button[onclick*="checkUpdate"]');
                    if (checkBtn) {
                        updateBtn = document.createElement('button');
                        updateBtn.textContent = '📥 Update';
                        updateBtn.className = 'primary btn-sm';
                        updateBtn.setAttribute('onclick', `showUpdateModal('${containerId}')`);
                        checkBtn.insertAdjacentElement('afterend', updateBtn);
                    }
                }
            } else if (actionsCell && (status === 'up-to-date' || status === 'latest')) {
                // Remove update button if it exists
                const updateBtn = actionsCell.querySelector('button[onclick*="showUpdateModal"]');
                if (updateBtn) {
                    updateBtn.remove();
                }
            }
        }

        function showNotification(message, type = 'info') {
            const notification = document.createElement('div');
            notification.className = `toast ${type}`;
            notification.textContent = message;

            document.body.appendChild(notification);

            setTimeout(() => {
                notification.classList.add('toast-out');
                setTimeout(() => notification.remove(), 300);
            }, 3000);
        }

// Auto-refresh functionality
        let refreshInterval;

        function startAutoRefresh() {
            // Refresh every 30 seconds
            refreshInterval = setInterval(refreshData, 30000);
        }

        function stopAutoRefresh() {
            if (refreshInterval) {
                clearInterval(refreshInterval);
            }
        }

        function refreshData() {
            // Show refreshing status
            const statusElement = document.getElementById('autoRefreshStatus');
            if (statusElement) {
                statusElement.textContent = 'Auto-refresh: UPDATING...';
                statusElement.className = 'refresh-updating';
            }

            // Fetch updated container data
            Promise.all([
                fetch('/api/containers').then(r => r.json()),
                fetch('/api/status').then(r => r.json())
            ])
            .then(([containers, status]) => {
                // Check if updates are in progress
                if (status.update_in_progress) {
                    // Updates in progress, keep showing updating status
                    if (statusElement) {
                        statusElement.textContent = 'Auto-refresh: UPDATING...';
                        statusElement.className = 'refresh-updating';
                    }
                } else {
                    // Updates complete, update the UI
                    updateHeaderStats(containers);
                    updateContainerTable(containers);

                    // Reset status
                    if (statusElement) {
                        statusElement.textContent = 'Auto-refresh: ON';
                        statusElement.className = '';
                    }
                }
            })
            .catch(error => {
                console.error('Error refreshing data:', error);
                // Check if error might be due to container updates in progress
                if (error.message && error.message.includes('fetch')) {
                    // Network error - might be due to server restarting during updates
                    if (statusElement) {
                        statusElement.textContent = 'Auto-refresh: RETRYING...';
                        statusElement.className = 'refresh-retrying';
                    }
                } else {
                    // Other error
                    if (statusElement) {
                        statusElement.textContent = 'Auto-refresh: ERROR';
                        statusElement.className = 'refresh-error';
                    }
                }
            });
        }

        function updateHeaderStats(containers) {
            // Update the stats cards
            const totalElement = document.querySelector('.header-stats .stat-card:first-child p');
            const updatesElement = document.querySelector('.header-stats .stat-card:nth-child(2) p');

            if (totalElement) {
                totalElement.textContent = containers.length || 0;
            }
            if (updatesElement) {
                // Count containers needing updates
                const updatesAvailable = containers.filter(container =>
                    container.update_info && container.update_info.needs_update
                ).length;
                updatesElement.textContent = updatesAvailable;
            }
        }

        function updateContainerTable(containers) {
            const tbody = document.querySelector('.container-table tbody');
            if (!tbody) return;

            // Get current rows for reference
            const currentRows = {};
            tbody.querySelectorAll('tr').forEach(row => {
                const containerId = row.getAttribute('data-container-id');
                if (containerId) {
                    currentRows[containerId] = row;
                }
            });

            // Update or create rows for each container
            containers.forEach(container => {
                let row = currentRows[container.id];
                const needsUpdate = container.update_info ? container.update_info.needs_update : false;
                const statusClass = getStatusClass(container, needsUpdate);

                if (row) {
                    // Update existing row
                    // Remove all status classes first
                    row.classList.remove('status-up-to-date', 'status-update-available', 'status-error', 'status-latest');
                    row.classList.add(statusClass);

                    // Update cells
                    const nameCell = row.cells[0];
                    const imageCell = row.cells[1];

                    if (nameCell) {
                        const name = container.name.startsWith('/') ? container.name.substring(1) : container.name;
                        nameCell.textContent = name.length > 30 ? name.substring(0, 27) + '...' : name;
                        nameCell.setAttribute('title', name);
                    }

                    if (imageCell) {
                        const image = container.image;
                        imageCell.innerHTML = `<code>${image.length > 50 ? image.substring(0, 47) + '...' : image}</code>`;
                        imageCell.setAttribute('title', container.image);
                    }

                    // Update action buttons
                    updateContainerButtons(row, container.id, needsUpdate);
                } else {
                    // Create new row
                    row = createContainerRow(container, statusClass, needsUpdate);
                    tbody.appendChild(row);
                }
            });

            // Remove rows for containers that no longer exist
            Object.keys(currentRows).forEach(containerId => {
                if (!containers.find(c => c.id === containerId)) {
                    currentRows[containerId].remove();
                }
            });
        }

        function getStatusClass(container, needsUpdate) {
            if (container.image.includes('latest')) {
                return 'status-latest';
            } else if (needsUpdate) {
                return 'status-update-available';
            } else {
                return 'status-up-to-date';
            }
        }

        function createContainerRow(container, statusClass, needsUpdate) {
            const row = document.createElement('tr');
            row.className = statusClass;
            row.setAttribute('data-container-id', container.id);

            const name = container.name.startsWith('/') ? container.name.substring(1) : container.name;
            const image = container.image;

            row.innerHTML = `
                <td title="${name}">${name.length > 30 ? name.substring(0, 27) + '...' : name}</td>
                <td title="${image}"><code>${image.length > 50 ? image.substring(0, 47) + '...' : image}</code></td>
                <td>
                    <div class="actions-cell">
                        ${!needsUpdate ? `<button onclick="checkUpdate('${container.id}')" class="secondary btn-sm">Check</button>` : ''}
                        ${needsUpdate ? `<button onclick="showUpdateModal('${container.id}')" class="primary btn-sm">Update</button>` : ''}
                    </div>
                </td>
            `;

            return row;
        }

        function updateContainerButtons(row, containerId, needsUpdate) {
            const actionsCell = row.cells[2];
            if (!actionsCell) return;

            // Clear all buttons first
            actionsCell.innerHTML = '';

            if (needsUpdate) {
                // Show only update button
                const updateBtn = document.createElement('button');
                updateBtn.textContent = 'Update';
                updateBtn.className = 'primary btn-sm';
                updateBtn.setAttribute('onclick', `showUpdateModal('${containerId}')`);
                actionsCell.appendChild(updateBtn);
            } else {
                // Show only check button
                const checkBtn = document.createElement('button');
                checkBtn.textContent = 'Check';
                checkBtn.className = 'secondary btn-sm';
                checkBtn.setAttribute('onclick', `checkUpdate('${containerId}')`);
                actionsCell.appendChild(checkBtn);
            }
        }

        // ========== SSE (Server-Sent Events) for real-time updates ==========
        let sseEventSource = null;

        function connectSSE() {
            if (sseEventSource) {
                sseEventSource.close();
            }

            sseEventSource = new EventSource('/api/events');

            sseEventSource.onopen = function() {
                console.log('SSE connected');
            };

            sseEventSource.addEventListener('status_update', function(e) {
                const data = JSON.parse(e.data);
                console.log('Status update:', data);
            });

            sseEventSource.addEventListener('image_pull_start', function(e) {
                const data = JSON.parse(e.data);
                showNotification(`Pulling image for ${data.container_name}...`, 'info');
            });

            sseEventSource.addEventListener('image_pull_complete', function(e) {
                const data = JSON.parse(e.data);
                showNotification(`Image pulled for ${data.container_name}`, 'success');
            });

            sseEventSource.addEventListener('container_stop', function(e) {
                const data = JSON.parse(e.data);
                showNotification(`Stopping ${data.container_name}...`, 'info');
            });

            sseEventSource.addEventListener('container_remove', function(e) {
                const data = JSON.parse(e.data);
                showNotification(`Removing ${data.container_name}...`, 'info');
            });

            sseEventSource.addEventListener('container_create', function(e) {
                const data = JSON.parse(e.data);
                showNotification(`Creating ${data.container_name}...`, 'info');
            });

            sseEventSource.addEventListener('container_start', function(e) {
                const data = JSON.parse(e.data);
                showNotification(`Starting ${data.container_name}...`, 'info');
            });

            sseEventSource.addEventListener('update_complete', function(e) {
                const data = JSON.parse(e.data);
                showNotification(`${data.container_name} updated successfully!`, 'success');

                // Update the UI - remove update button and show check button
                const row = findContainerRow(data.container_id);
                if (row) {
                    updateContainerButtons(row, data.container_id, false);
                    row.classList.remove('status-update-available');
                    row.classList.add('status-up-to-date');
                }

                // Refresh the container list to get updated state
                setTimeout(() => refreshData(), 2000);
            });

            sseEventSource.addEventListener('update_error', function(e) {
                const data = JSON.parse(e.data);
                showNotification(`Error updating ${data.container_name}: ${data.message}`, 'error');

                // Update UI to show error status
                const row = findContainerRow(data.container_id);
                if (row) {
                    row.classList.remove('status-update-available', 'status-up-to-date', 'status-latest');
                    row.classList.add('status-error');
                }
            });

            sseEventSource.onerror = function() {
                console.log('SSE connection error, reconnecting in 5 seconds...');
                setTimeout(connectSSE, 5000);
            };
        }

        // Start auto-refresh when page loads
        document.addEventListener('DOMContentLoaded', function() {
            startAutoRefresh();
            connectSSE(); // Start SSE connection
        });

        // Stop auto-refresh when page is not visible
        document.addEventListener('visibilitychange', function() {
            if (document.hidden) {
                stopAutoRefresh();
                // Close SSE connection when page is hidden
                if (sseEventSource) {
                    sseEventSource.close();
                    sseEventSource = null;
                }
            } else {
                startAutoRefresh();
                // Reconnect SSE when page becomes visible
                connectSSE();
                // Refresh immediately when page becomes visible again
                refreshData();
            }
        });

        // Table sorting functionality
        let currentSortColumn = -1;
        let currentSortDirection = 'none'; // 'asc', 'desc', or 'none'

        function setupTableSorting() {
            const table = document.getElementById('containerTable');
            if (!table) return;

            const headers = table.querySelectorAll('th');
            headers.forEach((header, columnIndex) => {
                header.addEventListener('click', () => {
                    sortTable(columnIndex, header.dataset.type);
                });
            });
        }

        function sortTable(columnIndex, columnType) {
            const table = document.getElementById('containerTable');
            if (!table) return;

            const tbody = table.querySelector('tbody');
            if (!tbody) return;

            const rows = Array.from(tbody.querySelectorAll('tr'));
            const headers = table.querySelectorAll('th');
            const currentHeader = headers[columnIndex];

            // Determine sort direction
            let direction = 'asc';
            if (currentSortColumn === columnIndex) {
                if (currentSortDirection === 'asc') {
                    direction = 'desc';
                } else if (currentSortDirection === 'desc') {
                    direction = 'asc';
                }
            }

            // Update header classes
            headers.forEach(h => {
                h.classList.remove('sort-asc', 'sort-desc', 'sort-none');
                h.classList.add('sort-none');
            });
            currentHeader.classList.remove('sort-none');
            currentHeader.classList.add(direction === 'asc' ? 'sort-asc' : 'sort-desc');

            // Sort rows
            rows.sort((a, b) => {
                let aVal, bVal;

                if (columnType === 'actions') {
                    // For actions column, sort by status (update available > latest > up to date)
                    aVal = getRowSortOrder(a);
                    bVal = getRowSortOrder(b);
                } else {
                    aVal = getCellValue(a, columnIndex);
                    bVal = getCellValue(b, columnIndex);
                }

                // Compare values
                let comparison = 0;
                if (typeof aVal === 'string' && typeof bVal === 'string') {
                    comparison = aVal.localeCompare(bVal);
                } else {
                    comparison = aVal - bVal;
                }

                return direction === 'asc' ? comparison : -comparison;
            });

            // Reorder rows in DOM
            rows.forEach(row => tbody.appendChild(row));

            // Update current sort state
            currentSortColumn = columnIndex;
            currentSortDirection = direction;
        }

        function getCellValue(row, columnIndex) {
            const cell = row.cells[columnIndex];
            if (!cell) return '';

            // Get text content, stripping any HTML tags
            return cell.textContent.trim();
        }

        function getRowSortOrder(row) {
            // Define sort priority based on status classes
            // Update available (highest priority) > Latest tag > Up to date
            if (row.classList.contains('status-update-available')) {
                return 1;
            } else if (row.classList.contains('status-latest')) {
                return 2;
            } else if (row.classList.contains('status-up-to-date')) {
                return 3;
            } else if (row.classList.contains('status-error')) {
                return 4;
            }
            return 5;
        }

        // Initialize sorting on page load
        document.addEventListener('DOMContentLoaded', function() {
            setupTableSorting();
        });

        // Handlers referenced by inline onclick attributes in the markup.
        // Top-level function declarations already land on window; this keeps
        // that contract explicit (and the linter honest about the references).
        Object.assign(window, {
            toggleTheme,
            checkAllUpdates,
            updateAllContainers,
            showUpdateModal,
            checkUpdate,
            confirmUpdate,
            closeModal,
            confirmBulkUpdate,
            closeBulkModal,
            closeDryRunResultsModal
        });

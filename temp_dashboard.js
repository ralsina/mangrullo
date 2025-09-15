
        let currentContainerId = null;
        // Reserved for future action tracking
        // let currentAction = null;

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

        async function checkUpdate(containerId) {
            const row = findContainerRow(containerId);
            if (!row) return;
            
            const button = row.querySelector('button[onclick*="checkUpdate"]');
            const originalText = button.textContent;
            
            button.textContent = 'Checking...';
            button.disabled = true;
            
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
            }
        }

        async function confirmUpdate() {
            if (!currentContainerId) return;
            
            const allowMajor = document.getElementById('allowMajor').checked;
            const row = findContainerRow(currentContainerId);
            if (!row) return;
            
            const button = row.querySelector('button[onclick*="showUpdateModal"]');
            const originalText = button.textContent;
            
            button.textContent = 'Updating...';
            button.disabled = true;
            closeModal();
            
            try {
                const response = await fetch(`/containers/${currentContainerId}/update`, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                    },
                    body: JSON.stringify({ allow_major: allowMajor })
                });
                
                const data = await response.json();
                
                if (data.updated) {
                    updateContainerStatus(currentContainerId, 'up-to-date', null, null);
                    showNotification('Container updated successfully!', 'success');
                    // Reload after a short delay to show the update
                    setTimeout(() => location.reload(), 1500);
                } else {
                    showNotification(`Update failed: ${data.error}`, 'error');
                    updateContainerStatus(currentContainerId, 'error', null, null);
                }
            } catch (error) {
                console.error('Error updating container:', error);
                showNotification('Update failed', 'error');
                updateContainerStatus(currentContainerId, 'error', null, null);
            } finally {
                button.textContent = originalText;
                button.disabled = false;
            }
        }

        async function checkAllUpdates() {
            showNotification('Checking all containers for updates...', 'info');
            
            try {
                const response = await fetch('/api/updates');
                const data = await response.json();
                
                data.forEach(container => {
                    if (container.needs_update) {
                        updateContainerStatus(container.id, 'update-available', 
                            container.update_info.local_version, 
                            container.update_info.remote_version);
                    } else {
                        updateContainerStatus(container.id, 'up-to-date', 
                            container.update_info.local_version, 
                            container.update_info.remote_version);
                    }
                });
                
                showNotification('Update check completed!', 'success');
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
            
            closeBulkModal();
            
            try {
                const response = await fetch('/api/updates', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                    },
                    body: JSON.stringify({ allow_major: allowMajor, dry_run: dryRun })
                });
                
                const data = await response.json();
                
                let successCount = 0;
                let failureCount = 0;
                
                data.forEach(result => {
                    if (result.updated) {
                        successCount++;
                        updateContainerStatus(result.container.id, 'up-to-date', null, null);
                    } else if (result.error) {
                        failureCount++;
                        updateContainerStatus(result.container.id, 'error', null, null);
                    }
                });
                
                const message = dryRun ? 
                    `Dry run completed: ${successCount} containers would be updated` :
                    `Update completed: ${successCount} successful, ${failureCount} failed`;
                
                showNotification(message, successCount > 0 ? 'success' : 'info');
                
                // Reload after a short delay to show updates
                if (!dryRun && successCount > 0) {
                    setTimeout(() => location.reload(), 1500);
                }
            } catch (error) {
                console.error('Error in bulk update:', error);
                showNotification('Bulk update failed', 'error');
            }
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
                        updateBtn.className = 'primary';
                        updateBtn.style.cssText = 'padding: 0.25rem 0.75rem; font-size: 0.875rem; line-height: 1.25;';
                        updateBtn.setAttribute('onclick', `showUpdateModal(\'${containerId}\')`);
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
            notification.style.cssText = `
                position: fixed;
                top: 20px;
                right: 20px;
                padding: 1rem;
                background: ${type === 'success' ? '#d4edda' : type === 'error' ? '#f8d7da' : '#d1ecf1'};
                color: ${type === 'success' ? '#155724' : type === 'error' ? '#721c24' : '#0c5460'};
                border-radius: 0.5rem;
                border: 1px solid ${type === 'success' ? '#c3e6cb' : type === 'error' ? '#f5c6cb' : '#bee5eb'};
                z-index: 1000;
                max-width: 300px;
                animation: slideIn 0.3s ease-out;
            `;
            notification.textContent = message;
            
            document.body.appendChild(notification);
            
            setTimeout(() => {
                notification.style.animation = 'slideOut 0.3s ease-out';
                setTimeout(() => notification.remove(), 300);
            }, 3000);
        }

        // Add CSS animations
        const style = document.createElement('style');
        style.textContent = `
            @keyframes slideIn {
                from { transform: translateX(100%); opacity: 0; }
                to { transform: translateX(0); opacity: 1; }
            }
            @keyframes slideOut {
                from { transform: translateX(0); opacity: 1; }
                to { transform: translateX(100%); opacity: 0; }
            }
        `;
        document.head.appendChild(style);
    
// Auto-refresh functionality
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
    
    const name = container.name.replace(/^\//, '');
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
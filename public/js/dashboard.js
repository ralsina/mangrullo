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
            body: JSON.stringify({ allow_major: false })
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
    notification.textContent = message;
    notification.style.cssText = `
        position: fixed;
        top: 20px;
        right: 20px;
        padding: 1rem;
        border-radius: 0.5rem;
        color: white;
        z-index: 1000;
        animation: slideIn 0.3s ease-out;
    `;

    // Set background color based on type
    switch (type) {
        case 'success':
            notification.style.backgroundColor = '#28a745';
            break;
        case 'error':
            notification.style.backgroundColor = '#dc3545';
            break;
        case 'info':
            notification.style.backgroundColor = '#007bff';
            break;
    }

    document.body.appendChild(notification);

    setTimeout(() => {
        notification.remove();
    }, 3000);
}
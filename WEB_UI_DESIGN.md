# Mangrullo Web UI Design Document

## Overview

This document describes the design and implementation plan for a web-based user interface for Mangrullo, a Docker container update automation tool. The web UI will provide a modern, responsive interface for monitoring and managing Docker container updates.

## Goals

1. **Visual Monitoring**: Provide a dashboard view of all running containers and their update status
2. **Interactive Management**: Allow users to check for updates, update containers, and view logs
3. **Real-time Updates**: Show live status updates and notifications
4. **Bulk Operations**: Enable updating multiple containers at once
5. **Mobile Responsive**: Work well on both desktop and mobile devices

## Technology Stack

### Backend
- **Kemal**: Fast, lightweight web framework for Crystal
- **Kilt**: Template engine for HTML rendering
- **Crystal**: High-performance programming language
- **Existing Mangrullo modules**: Docker client, image checker, update manager

### Frontend
- **Pico.css**: Lightweight, semantic CSS framework
- **Vanilla JavaScript**: No heavy framework dependencies
- **HTML5**: Modern, semantic markup
- **WebSocket**: Real-time communication (optional)

### Architecture
```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Browser      │    │   Kemal Server  │    │   Docker API    │
│                │    │                │    │                │
│ ┌─────────────┐ │    │ ┌─────────────┐ │    │ ┌─────────────┐ │
│ │ Pico.css    │ │◄──►│ │ Web Server  │ │◄──►│ │ Containers  │ │
│ │ Templates   │ │    │ │ Routes      │ │    │ │ Images      │ │
│ │ JavaScript  │ │    │ │ API         │ │    │ │ Networks    │ │
│ └─────────────┘ │    │ └─────────────┘ │    │ └─────────────┘ │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## Features

### 1. Dashboard (Main Page)
**URL**: `/`

**Purpose**: Overview of all running containers and their update status

**Components**:
- Header with app title and navigation
- Summary statistics (total containers, updates available)
- Container list with:
  - Container name and ID
  - Current image tag
  - Update status indicator
  - Last checked timestamp
  - Quick actions (Check Update, Update)
- Action bar for bulk operations
- Real-time status indicators

**Status Indicators**:
- 🟢 Up to date
- 🟡 Update available
- 🔴 Unknown/error
- ⚪ Latest tag (always check)

### 2. Container Details Page
**URL**: `/containers/:id`

**Purpose**: Detailed view and management of individual containers

**Components**:
- Container information (name, ID, image, status)
- Version comparison (current vs available)
- Update history
- Action buttons:
  - Check for updates
  - Update container
  - Restart container
  - View logs
- Logs viewer with real-time updates
- Configuration summary

### 3. API Endpoints

#### Container Management
- `GET /api/containers` - List all containers
- `GET /api/containers/:id` - Get container details
- `POST /api/containers/:id/check-update` - Check for updates
- `POST /api/containers/:id/update` - Update container
- `POST /api/containers/:id/restart` - Restart container
- `GET /api/containers/:id/logs` - Get container logs

#### Bulk Operations
- `GET /api/updates` - Check all containers for updates
- `POST /api/updates` - Update multiple containers

#### System
- `GET /health` - Health check

### 4. Real-time Features (Optional)

#### WebSocket Support
- Live status updates
- Progress notifications for long-running operations
- Log streaming

#### Auto-refresh
- Periodic status checks
- Manual refresh button

## User Interface Design

### Color Scheme
Using Pico.css default color scheme:
- **Primary**: #007bff (blue for actions)
- **Success**: #28a745 (green for up-to-date)
- **Warning**: #ffc107 (yellow for updates available)
- **Danger**: #dc3545 (red for errors)
- **Light**: #f8f9fa (backgrounds)
- **Dark**: #343a40 (text)

### Layout Structure
```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Mangrullo - Docker Container Updates</title>
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@picocss/pico@1/css/pico.min.css">
</head>
<body>
  <header>
    <nav>
      <!-- Navigation -->
    </nav>
  </header>
  
  <main>
    <!-- Main content -->
  </main>
  
  <footer>
    <!-- Footer -->
  </footer>
  
  <script>
    // JavaScript for interactivity
  </script>
</body>
</html>
```

### Component Templates

#### Container Card
```html
<div class="card">
  <article>
    <header>
      <h3>Container Name</h3>
      <span class="status-badge status-update-available">Update Available</span>
    </header>
    <p><strong>Image:</strong> nginx:1.2.3</p>
    <p><strong>Status:</strong> Running</p>
    <footer>
      <button onclick="checkUpdate('container-id')">Check Update</button>
      <button onclick="updateContainer('container-id')">Update</button>
    </footer>
  </article>
</div>
```

#### Update Modal
```html
<dialog id="update-modal">
  <article>
    <header>
      <h3>Update Container</h3>
      <button aria-label="Close" rel="prev"></button>
    </header>
    <p>Are you sure you want to update this container?</p>
    <label>
      <input type="checkbox" name="allow-major" />
      Allow major version upgrades
    </label>
    <footer>
      <button onclick="confirmUpdate()">Update</button>
      <button onclick="closeModal()" aria-label="Close">Cancel</button>
    </footer>
  </article>
</dialog>
```

## Implementation Plan

### Phase 1: Basic Web Interface
1. [x] Add Kemal dependency
2. [ ] Create basic web server structure
3. [ ] Implement HTML templates with Pico.css
4. [ ] Create dashboard page
5. [ ] Add container list view

### Phase 2: Core Functionality
1. [ ] Implement container details page
2. [ ] Add update checking functionality
3. [ ] Implement container updates
4. [ ] Add error handling and validation

### Phase 3: Advanced Features
1. [ ] Add bulk operations
2. [ ] Implement real-time updates (WebSocket)
3. [ ] Add log viewing
4. [ ] Add container restart functionality

### Phase 4: Polish and Documentation
1. [ ] Responsive design improvements
2. [ ] Loading states and spinners
3. [ ] Better error messages
4. [ ] Update documentation

## Security Considerations

1. **Authentication**: Currently runs locally, consider adding auth for remote access
2. **Authorization**: Container operations require appropriate permissions
3. **Input Validation**: All user input should be validated
4. **CSRF Protection**: Use tokens for state-changing operations
5. **Rate Limiting**: Prevent abuse of API endpoints

## Performance Considerations

1. **Caching**: Cache Docker API responses where appropriate
2. **Pagination**: For large numbers of containers
3. **Lazy Loading**: Load container details on demand
4. **Connection Pooling**: Reuse Docker client connections

## Testing Strategy

1. **Unit Tests**: Test individual components and utilities
2. **Integration Tests**: Test API endpoints and Docker integration
3. **End-to-End Tests**: Test complete user workflows
4. **Browser Testing**: Test across different browsers and devices

## File Structure

```
src/
├── web.cr                 # Web server entry point
├── web_server.cr          # Main web server class
├── web_views.cr           # View templates and rendering
├── public/               # Static assets
│   ├── css/
│   ├── js/
│   └── images/
└── templates/            # HTML templates
    ├── layout.ecr
    ├── dashboard.ecr
    ├── container_details.ecr
    └── partials/
```

## Success Metrics

1. **Functionality**: All core container operations work via web interface
2. **Performance**: Page loads in < 2 seconds with 50 containers
3. **Usability**: Intuitive interface requiring no documentation
4. **Reliability**: Graceful error handling and recovery
5. **Mobile**: Responsive design works on mobile devices

## Future Enhancements

1. **User Authentication**: Multi-user support with permissions
2. **Scheduled Updates**: Web-based scheduling configuration
3. **Notifications**: Email/webhook notifications
4. **Container Metrics**: Resource usage graphs
5. **Image History**: View image update history
6. **Export/Import**: Configuration backup and restore
7. **Themes**: Dark/light mode toggle
8. **API Documentation**: Swagger/OpenAPI documentation

## Conclusion

The web UI will make Mangrullo more accessible and user-friendly while maintaining the reliability and performance of the core CLI tool. The modular design allows for incremental development and easy extension.
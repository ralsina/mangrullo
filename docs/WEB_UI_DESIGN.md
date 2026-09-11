# Mangrullo Web UI Design Document

## Overview

This document outlines the design and implementation plan for Mangrullo's web
interface. The web UI provides a modern, responsive dashboard for monitoring
and managing Docker container updates through a browser interface.

## Goals

1. **Visual Monitoring**: Provide a dashboard view of all running containers and their update status
2. **Interactive Management**: Allow users to check for updates, update containers, and view logs
3. **Real-time Updates**: Show live status updates and notifications
4. **Bulk Operations**: Enable updating multiple containers at once
5. **Mobile Responsive**: Work well on both desktop and mobile devices

## Current Status

The web interface is fully implemented with comprehensive functionality:

### ✅ Completed Features

- **Basic Web Server**: Kemal-based HTTP server running on port 3000 (configurable via `MANGRULLO_WEB_PORT`/`MANGRULLO_WEB_HOST`)
- **Dashboard Page**: Overview of all running containers and their update status
- **Container List**: Display of containers with update status indicators
- **Update Checking**: Web-based update detection functionality
- **Container Updates**: Web-triggered container recreation and updates
- **HTML Templates**: ECR template with a token-driven "Mission Control" theme
- **Error Handling**: Graceful error handling and user-friendly messages
- **Real-time Updates**: Auto-refresh (every 30 seconds) plus live Server-Sent Events
- **Bulk Operations**: Multi-container updates queued through the job queue, with dry run support
- **Embedded Static Assets**: All CSS, JavaScript, and images baked into binary
- **Theme Toggle**: Dark (default) and light modes, persisted in `localStorage`
- **State Management**: Shared state between web requests and background operations
- **Custom Branding**: Cell tower icons and favicons throughout interface
- **Typography**: Chivo, Chivo Mono and Space Grotesk Google Fonts
- **Dry Run Modal**: Comprehensive results display with CLI-like output
- **Modal Improvements**: Proper close button positioning and responsive design
- **Bulk Update Modal**: Dry run checkbox and major version upgrade controls
- **Button State Management**: Proper onclick attribute handling during operations
- **Notification System**: Token-colored toast notifications for user feedback
- **Container Restart**: Direct container restart via the API
- **Optional HTTP Basic Auth**: Enabled via `MANGRULLO_WEB_USER`/`MANGRULLO_WEB_PASSWORD`

### 🚧 In Progress

- **Log Viewing**: Container log viewing

### 📋 Planned Features

- **Metrics**: Performance and usage metrics
- **Scheduling**: Web-based update scheduling
- **Notifications**: Email/webhook notifications
- **API Documentation**: Swagger/OpenAPI documentation

## Technology Stack

### Backend

- **Kemal**: Fast, lightweight web framework for Crystal
- **ECR**: Crystal's built-in template engine for HTML rendering
- **Crystal**: High-performance programming language
- **Baked File System**: Embedded static assets for easy deployment
- **Server-Sent Events**: Live update progress pushed to connected dashboards
- **Job Queue**: Bulk updates are enqueued and polled instead of blocking requests
- **State Manager**: Shared state management for web operations
- **Existing Mangrullo modules**: Docker client, image checker, update manager

### Frontend

- **Pico.css v2** (self-hosted): reskinned through `--pico-*` custom properties
- **Token-driven theme**: `data-theme="dark|light"` selects a CSS custom
  property set (Mission Control palette: dark navy panels, teal accent)
- **Vanilla JavaScript**: served as a baked `/js/dashboard.js` asset; only the
  pre-paint theme bootstrap stays inline
- **HTML5**: Modern, semantic markup
- **Auto-refresh**: Periodic status updates (every 30 seconds)
- **Server-Sent Events**: `EventSource` connection to `/api/events`

### Architecture

```text
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

**Status**: Not implemented (planned). The dashboard is a single page;
per-container actions (check, update) live in the container table, and
restart is available through the API (`POST /containers/:id/restart`).

### 3. API Endpoints

#### Pages

- `GET /` - Dashboard
- `GET /health` - Health check (kept open when Basic auth is enabled)

#### Container Management

- `POST /containers/:id/check-update` - Force an update check for one container
- `POST /containers/:id/update` - Queue an update job for one container
- `POST /containers/:id/restart` - Restart container

#### Bulk Operations

- `GET /api/updates` - Update info for all containers
- `POST /api/updates` - Dry runs execute synchronously; real updates enqueue
  one job per container and answer `202` with `{queued, count, job_ids}`

#### Job Status

- `GET /api/jobs/:job_id` - Job status (retained ~10 minutes after finishing)
- `GET /api/containers/:container_id/jobs` - Jobs for one container

#### System

- `GET /api/status` - State manager status (includes `update_in_progress`)
- `GET /api/containers` - All containers with update info
- `POST /api/refresh` - Force a refresh of all containers (409 if in progress)
- `GET /api/events` - SSE stream of live update events

All routes are protected by HTTP Basic auth when `MANGRULLO_WEB_USER` and
`MANGRULLO_WEB_PASSWORD` are set (`/health` excepted).

### 4. Real-time Features (Implemented)

#### Server-Sent Events

The dashboard opens an `EventSource` on `/api/events`. The endpoint registers
the client, streams keep-alive comments, and the update flow broadcasts
events: `image_pull_start`, `image_pull_complete`, `container_stop`,
`container_remove`, `container_create`, `container_start`, `update_complete`,
`update_error`, `status_update`.

#### Auto-refresh

- Periodic status checks every 30 seconds (paused while the tab is hidden)
- SSE events trigger targeted UI updates and refreshes

## User Interface Design

### Color Scheme

Token-driven, selected by `<html data-theme="dark|light">` (Mission Control
palette, grafito-style):

| Token | Dark | Light |
|-------|------|-------|
| `--bg` | `#101418` | `#f2f5f4` |
| `--panel` | `#161b22` | `#ffffff` |
| `--line` | `#29313c` | `#d3dcda` |
| `--txt` | `#dfe6ee` | `#1d2530` |
| `--accent` | `#4cc2a9` (teal) | `#178f77` |
| `--ok` | `#7ec9a1` | `#3e7d5c` |
| `--warn` | `#e9a23b` | `#b07414` |
| `--err` | `#f0635a` | `#c73e34` |
| `--info` | `#58a6ff` | `#2b6cb0` |

Pico.css v2 is reskinned through its `--pico-*` custom properties, and
container status is conveyed with severity-colored left borders on table rows.

### Layout Structure

The dashboard is a single ECR template (`src/templates/dashboard.ecr`) with a
sticky topbar (brand, auto-refresh indicator, theme toggle, Check/Update
actions), two stat cards, a sortable container table, dialogs for update and
dry-run confirmations, and a footer. JavaScript lives in
`public/js/dashboard.js` (baked into the binary); only a small pre-paint
theme bootstrap remains inline in `<head>`.

### Component Templates

#### Container Table Row

```html
<tr class="status-update-available" data-container-id="abc123">
  <td title="my-app">my-app</td>
  <td title="nginx:1.2.3"><code>nginx:1.2.3</code></td>
  <td>
    <div class="actions-cell">
      <button onclick="showUpdateModal('abc123')" class="primary btn-sm">Update</button>
    </div>
  </td>
</tr>
```

Row status (`status-up-to-date`, `status-update-available`, `status-latest`,
`status-error`) drives a severity-colored left border on the first cell.

#### Update Modal

```html
<dialog id="updateModal">
  <article>
    <header>
      <h3>Update Container</h3>
      <button aria-label="Close" class="close" onclick="closeModal()"></button>
    </header>
    <p>Are you sure you want to update this container?</p>
    <label>
      <input type="checkbox" id="allowMajor" name="allow_major" />
      Allow major version upgrades
    </label>
    <footer>
      <button onclick="confirmUpdate()" class="primary">Update Container</button>
      <button onclick="closeModal()" aria-label="Close" class="secondary">Cancel</button>
    </footer>
  </article>
</dialog>
```

## Implementation Plan

### Phase 1: Basic Web Interface ✓

1. [x] Add Kemal dependency
2. [x] Create basic web server structure
3. [x] Implement HTML templates with Pico.css
4. [x] Create dashboard page
5. [x] Add container list view

### Phase 2: Core Functionality ✓

1. [x] Implement container details page
2. [x] Add update checking functionality
3. [x] Implement container updates
4. [x] Add error handling and validation

### Phase 3: Advanced Features ✅

1. [x] Add bulk operations (queued through the job queue)
2. [x] Implement real-time updates (auto-refresh every 30 seconds + SSE)
3. [x] Add container restart functionality
4. [ ] Add log viewing

### Phase 4: Polish and Documentation ✅

1. [x] Responsive design improvements
2. [x] Loading states and spinners
3. [x] Better error messages
4. [x] Update documentation
5. [x] Custom branding with cell tower icons
6. [x] Typography improvements with Chivo fonts
7. [x] Comprehensive dry run modal
8. [x] Favicon integration

## Security Considerations

1. **Authentication**: Implemented as optional HTTP Basic auth (`MANGRULLO_WEB_USER`/`MANGRULLO_WEB_PASSWORD`), constant-time credential comparison, `/health` exempt
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

```text
src/
├── web.cr                # Web server entry point (Kemal.run)
├── web_server.cr         # Routes, auth middleware, SSE endpoint, error handlers
├── web_views.cr          # Dashboard rendering (ECR)
├── templates/
│   └── dashboard.ecr     # Dashboard template
├── static_assets.cr      # Bakes public/ into the binary
├── sse.cr                # Server-Sent Events registry and broadcast
├── web_auth.cr           # Optional HTTP Basic authentication
├── update_job_queue.cr   # Background update jobs with status retention
├── state_manager.cr      # Shared state management
├── container_state.cr    # Container state data structures
└── public/               # Source static assets (baked into binary)
    ├── css/
    │   ├── pico.min.css  # Pico v2, self-hosted
    │   └── dashboard.css # Token-driven theme
    ├── js/
    │   └── dashboard.js  # Dashboard behavior
    ├── favicon.svg
    └── favicon.ico
```

**Note**: Static assets are now baked directly into the binary using the `baked_file_system` and `baked_file_handler` libraries, eliminating the need for separate static file deployment.

## Success Metrics

1. **Functionality**: All core container operations work via web interface
2. **Performance**: Page loads in < 2 seconds with 50 containers
3. **Usability**: Intuitive interface requiring no documentation
4. **Reliability**: Graceful error handling and recovery
5. **Mobile**: Responsive design works on mobile devices

## Future Enhancements

1. **Scheduled Updates**: Web-based scheduling configuration
2. **Notifications**: Email/webhook notifications
3. **Container Metrics**: Resource usage graphs
4. **Image History**: View image update history
5. **Export/Import**: Configuration backup and restore
6. **Log Viewing**: Container log viewer
7. **API Documentation**: Swagger/OpenAPI documentation

## Conclusion

The web UI will make Mangrullo more accessible and user-friendly while maintaining the reliability and performance of the core CLI tool. The modular design allows for incremental development and easy extension.

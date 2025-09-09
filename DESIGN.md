# Mangrullo Design Document

## Overview
Mangrullo is a Crystal implementation of a Watchtower-like Docker container update automation tool.

## Core Features
- Monitor running Docker containers and their image versions
- Check for new image versions
- Calculate if updates are needed (with major version upgrade control)
- Perform graceful container recreation with new images (like Watchtower)
- Container-specific filtering (check only specified containers)
- Flexible container name matching (handles both "name" and "/name")
- Multi-registry support with authentication

## Architecture

### Dependencies
- `marghidanu/docr` - Docker API client for Crystal
- `ralsina/docopt.cr` - Command line argument parsing
- `kemalcr/kemal` - Web framework (for web interface)
- `jeromegn/kilt` - Template engine (for web interface)
- Standard Crystal library for HTTP, JSON, logging

### Core Modules

#### 1. Mangrullo::DockerClient
- **Purpose**: Interface with Docker daemon
- **Responsibilities**:
  - Connect to Docker socket
  - List running containers
  - Get container details (image, labels, etc.)
  - Pull images
  - Container recreation (stop, remove, create, start)
  - Container configuration preservation
- **Key Methods**:
  - `running_containers`
  - `get_container_info(id : String)`
  - `pull_image(image_name : String, tag : String)`
  - `recreate_container_with_new_image(container_id : String, new_image : String)`
  - `stop_container(container_id : String)`
  - `remove_container(container_id : String)`
  - `create_container_from_inspect_data(image_name : String, container_name : String, inspect_data : String)`

#### 2. Mangrullo::ImageChecker
- **Purpose**: Check for image updates
- **Responsibilities**:
  - Compare local and remote image digests
  - Handle major version upgrade logic
  - Multi-registry support with authentication
  - Registry mapping (lscr.io → ghcr.io)
  - Determine if update is needed
- **Key Methods**:
  - `needs_update?(container : ContainerInfo, allow_major_upgrade : Bool) : Bool`
  - `get_remote_image_digest(image_name : String) : String?`
  - `get_local_image_digest(image_name : String) : String?`
  - `get_image_update_info(image_name : String)`
  - `extract_version_from_image(image_name : String) : Version?`
  - `get_update_status(container : ContainerInfo)`

#### 3. Mangrullo::UpdateManager
- **Purpose**: Coordinate the update process
- **Responsibilities**:
  - Main update workflow with container recreation
  - Container filtering and flexible name matching
  - Handle update scheduling
  - Logging and error handling
  - Dry run functionality
- **Key Methods**:
  - `check_and_update_containers(allow_major_upgrade : Bool = false, container_names : Array(String) = [] of String)`
  - `update_container(container : ContainerInfo, allow_major_upgrade : Bool = false)`
  - `get_containers_needing_update(allow_major_upgrade : Bool = false, container_names : Array(String) = [] of String)`
  - `dry_run(allow_major_upgrade : Bool = false, container_names : Array(String) = [] of String)`
  - `get_update_summary(allow_major_upgrade : Bool = false, container_names : Array(String) = [] of String)`

#### 4. Mangrullo::Config
- **Purpose**: Configuration management
- **Responsibilities**:
  - Parse command line arguments using Docopt
  - Handle container name filtering
  - Default configuration
- **Key Settings**:
  - `interval` (check interval in seconds)
  - `allow_major_upgrade` (boolean)
  - `docker_socket_path` (default: "/var/run/docker.sock")
  - `log_level`
  - `container_names` (array of specific containers to check)
  - `once` (run once and exit)
  - `dry_run` (show what would be updated)

#### 5. Mangrullo::Types
- **Purpose**: Type definitions
- **Key Structs**:
  - `ContainerInfo` - container details
  - `ImageInfo` - image metadata
  - `Version` - semantic version parsing and comparison

#### 6. Mangrullo::WebServer (Optional)
- **Purpose**: Web interface for monitoring and management
- **Responsibilities**:
  - HTTP server using Kemal
  - Container status dashboard
  - API endpoints for container operations
- **Key Methods**:
  - `start_server`
  - Container management endpoints
  - Status monitoring

#### 7. Mangrullo::ErrorHandling
- **Purpose**: Centralized error management
- **Responsibilities**:
  - Consistent error handling across modules
  - User-friendly error messages
  - Graceful degradation

## Main Workflow

1. **Initialize**:
   - Parse configuration (including container name filtering)
   - Connect to Docker daemon
   - Set up logging

2. **Monitor Loop**:
   - List running containers (or filter to specific containers)
   - For each container:
     - Get current image digest
     - Check remote registry for updates
     - Compare versions (respecting major upgrade flag)
     - If update needed: pull image → recreate container with new image

3. **Container Recreation Process**:
   - Stop the running container
   - Remove the old container to free up the name
   - Capture container configuration using `docker inspect`
   - Create new container with same configuration but new image
   - Start the new container
   - Verify the recreation worked

4. **Container Name Matching**:
   - Support flexible matching (both "container" and "/container")
   - Normalize input names for consistent comparison
   - Filter containers if specific names provided

5. **Scheduling**:
   - Run checks at configured intervals
   - Handle graceful shutdown

## Implementation Plan

### Phase 1: Core Infrastructure ✓
1. Add `docr` and `docopt.cr` dependencies to shard.yml
2. Implement basic Docker client wrapper
3. Create type definitions

### Phase 2: Update Logic ✓
1. Implement image version checking
2. Add major version upgrade logic
3. Create update manager

### Phase 3: Application Structure ✓
1. Add configuration system
2. Implement main CLI interface
3. Add logging

### Phase 4: Container Recreation ✓
1. Implement container recreation (not just restart)
2. Add configuration preservation
3. Add verification and error handling

### Phase 5: Container Filtering ✓
1. Add container name filtering
2. Implement flexible name matching
3. Update all methods to support filtering

### Phase 6: Multi-Registry Support ✓
1. Add registry authentication
2. Implement lscr.io → ghcr.io mapping
3. Support multiple registry types

### Phase 7: Testing ✓
1. Unit tests for all modules (56 examples)
2. Integration tests for critical functionality
3. Test edge cases and error conditions

### Phase 8: Web Interface (Framework) ✓
1. Add Kemal web framework
2. Create basic web server structure
3. Add web views templates

### Phase 9: Documentation and Polish ✓
1. Update all documentation
2. Add comprehensive examples
3. Finalize error handling

## Configuration Options

### Docopt Usage String

```
Mangrullo - Docker container update automation tool

Usage:
  mangrullo [--interval=<seconds>] [--allow-major] [--socket=<path>] 
           [--log-level=<level>] [--once] [--help] [--version]

Options:
  --interval=<seconds>   Check interval in seconds [default: 300]
  --allow-major          Allow major version upgrades
  --socket=<path>        Docker socket path [default: /var/run/docker.sock]
  --log-level=<level>    Log level (debug, info, warn, error) [default: info]
  --once                 Run once and exit
  --help                 Show this help message
  --version              Show version information
```

Environment Variables:
- `MANGRULLO_INTERVAL`
- `MANGRULLO_ALLOW_MAJOR_UPGRADE`
- `MANGRULLO_DOCKER_SOCKET`
- `MANGRULLO_LOG_LEVEL`

## File Structure

```
src/
├── mangrullo.cr              # Main module and CLI
├── docker_client.cr          # Docker API wrapper
├── image_checker.cr          # Image update logic
├── update_manager.cr         # Update coordination
├── config.cr                 # Configuration management
└── types.cr                  # Type definitions

spec/
├── docker_client_spec.cr
├── image_checker_spec.cr
├── update_manager_spec.cr
├── config_spec.cr
└── types_spec.cr
```

## Testing Strategy

- **Unit Tests**: Mock Docker API responses
- **Integration Tests**: Use test containers
- **Version Parsing Tests**: Edge cases for version comparison
- **Configuration Tests**: Argument parsing and environment variables
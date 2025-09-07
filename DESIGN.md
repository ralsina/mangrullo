# Mangrullo Design Document

## Overview
Mangrullo is a Crystal implementation of a Watchtower-like Docker container update automation tool.

## Core Features
- Monitor running Docker containers and their image versions
- Check for new image versions
- Calculate if updates are needed (with major version upgrade control)
- Perform graceful container restarts with new images

## Architecture

### Dependencies
- `marghidanu/docr` - Docker API client for Crystal
- `ralsina/docopt.cr` - Command line argument parsing
- Standard Crystal library for HTTP, JSON, logging

### Core Modules

#### 1. Mangrullo::DockerClient
- **Purpose**: Interface with Docker daemon
- **Responsibilities**:
  - Connect to Docker socket
  - List running containers
  - Get container details (image, labels, etc.)
  - Pull images
  - Restart containers
- **Key Methods**:
  - `list_containers(filter : Hash(String, String) = {} of Hash(String, String))`
  - `get_container_info(id : String)`
  - `pull_image(image_name : String)`
  - `restart_container(id : String)`

#### 2. Mangrullo::ImageChecker
- **Purpose**: Check for image updates
- **Responsibilities**:
  - Compare local and remote image digests
  - Handle major version upgrade logic
  - Determine if update is needed
- **Key Methods**:
  - `needs_update?(container_info : ContainerInfo, allow_major_upgrade : Bool) : Bool`
  - `get_remote_image_digest(image_name : String) : String?`
  - `parse_version_tag(tag : String) : Version`

#### 3. Mangrullo::UpdateManager
- **Purpose**: Coordinate the update process
- **Responsibilities**:
  - Main update workflow
  - Handle update scheduling
  - Logging and error handling
- **Key Methods**:
  - `check_and_update_containers(allow_major_upgrade : Bool = false)`
  - `update_container(container_id : String, allow_major_upgrade : Bool = false)`

#### 4. Mangrullo::Config
- **Purpose**: Configuration management
- **Responsibilities**:
  - Parse command line arguments using Docopt
  - Handle environment variables
  - Default configuration
- **Key Settings**:
  - `interval` (check interval in seconds)
  - `allow_major_upgrade` (boolean)
  - `docker_socket_path` (default: "/var/run/docker.sock")
  - `log_level`

#### 5. Mangrullo::Types
- **Purpose**: Type definitions
- **Key Structs**:
  - `ContainerInfo` - container details
  - `ImageInfo` - image metadata
  - `Version` - semantic version parsing

## Main Workflow

1. **Initialize**:
   - Parse configuration
   - Connect to Docker daemon
   - Set up logging

2. **Monitor Loop**:
   - List running containers
   - For each container:
     - Get current image digest
     - Check remote registry for updates
     - Compare versions (respecting major upgrade flag)
     - If update needed: pull image → restart container

3. **Scheduling**:
   - Run checks at configured intervals
   - Handle graceful shutdown

## Implementation Plan

### Phase 1: Core Infrastructure
1. Add `docr` and `docopt.cr` dependencies to shard.yml
2. Implement basic Docker client wrapper
3. Create type definitions

### Phase 2: Update Logic
1. Implement image version checking
2. Add major version upgrade logic
3. Create update manager

### Phase 3: Application Structure
1. Add configuration system
2. Implement main CLI interface
3. Add logging

### Phase 4: Testing
1. Unit tests for all modules
2. Integration tests with Docker

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
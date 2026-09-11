# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Crystal Language project called "mangrullo" - a Docker container update automation tool similar to Watchtower. The project is functional and includes container monitoring, update detection, container recreation, and filtering capabilities. It follows standard Crystal conventions with comprehensive tests and a modular architecture.

## Development Commands

### Building and Running

- `shards build` - Build all targets
- `shards build mangrullo` - Build CLI target
- `shards build mangrullo-web` - Build web interface target
- `crystal build src/mangrullo.cr` - Compile the CLI
- `crystal run src/mangrullo.cr` - Run the CLI
- `crystal tool format` - Format code according to Crystal style guidelines
- `ameba --fix` - Fix linting issues automatically

### Testing

- `crystal spec` - Run all tests
- `crystal spec spec/mangrullo_spec.cr` - Run main test file
- `crystal spec --verbose` - Run tests with detailed output

### Dependencies

- `shards install` - Install dependencies from shard.yml
- `shards build` - Build all targets using shards
- `shards build mangrullo` - Build CLI target
- `shards build mangrullo-web` - Build web interface target

## Project Structure

### Source Files

- `src/mangrullo.cr` - Main CLI entry point
- `src/cli.cr` - CLI interface and main loop
- `src/config.cr` - Configuration management using Docopt
- `src/types.cr` - Core data structures and version comparison
- `src/docker_client.cr` - Docker API wrapper and container operations
- `src/image_checker.cr` - Image update detection and registry access
- `src/update_manager.cr` - Update coordination with container filtering
- `src/update_job_queue.cr` - Background update jobs with status retention
- `src/web.cr` - Web interface entry point (Kemal.run)
- `src/web_server.cr` - Kemal routes, auth middleware, SSE endpoint
- `src/web_views.cr` - Dashboard rendering
- `src/templates/dashboard.ecr` - Dashboard template
- `src/static_assets.cr` - Bakes `public/` (CSS, JS, favicons) into the binary
- `src/sse.cr` - Server-Sent Events registry and broadcast
- `src/web_auth.cr` - Optional HTTP Basic authentication
- `src/state_manager.cr` - Shared state management for web interface
- `src/container_state.cr` - Container state data structures
- `src/error_handling.cr` - Centralized error management
- `src/version.cr` - Single-sourced version constant

### Configuration

- `shard.yml` - Project dependencies and build targets
- `shard.lock` - Locked dependency versions
- `spec/mangrullo_spec.cr` - Test suite
- `spec/spec_helper.cr` - Test configuration

## Key Features Implemented

- **Container Monitoring**: Automatically detects running Docker containers
- **Update Detection**: Version comparison for versioned tags, digest comparison for moving tags (latest, postgres:16, digest pins)
- **Target Image Resolution**: Updates pull the newer tag, not the stale one
- **Rollback-safe Recreation**: Old container preserved as a backup and restored if a replacement fails
- **Container Filtering**: Check specific containers by name with flexible matching
- **Multi-Registry Support**: Docker Hub, GHCR, lscr.io (with proper mapping), registry ports
- **Registry Credentials**: Uses `~/.docker/config.json` for private images
- **Semantic Versioning**: Intelligent version comparison with major upgrade control
- **Dry Run Mode**: Test updates without making changes with comprehensive results modal
- **Full Web Interface**: Mission Control themed dashboard with dark/light toggle
- **Bulk Operations**: Async updates through a job queue with dry run support
- **Real-time Events**: Server-Sent Events stream update progress to the dashboard
- **Optional HTTP Basic Auth**: Constant-time comparison, `/health` exempt
- **Custom Branding**: Cell tower icons and favicon throughout interface
- **Auto-refresh Dashboard**: Real-time container status updates every 30 seconds
- **Embedded Static Assets**: All web assets baked into binary for easy deployment
- **Multi-architecture Builds**: Static binaries for Linux AMD64 and ARM64
- **Comprehensive Testing**: Unit tests for all major functionality (184 examples passing)
- **CI/CD Integration**: GitHub Actions with Ameba linting and automated testing

## Code Style

Follow Crystal Language conventions:

- Use 2-space indentation
- Module names are CamelCase
- Constants are UPPER_SNAKE_CASE
- Method names are snake_case
- Use `crystal tool format` for formatting
- Avoid `not_nil!` - use proper nilable handling
- Prefer `unless` over `if !` for negative conditions

## Current State

The project is fully functional with:

- Complete CLI implementation with all planned features
- Container recreation with rollback safety (updates containers, never destroys them)
- Flexible container name matching (handles both "name" and "/name")
- Comprehensive test suite (184 examples, 0 failures)
- Web interface with theme toggle, SSE live events and optional Basic auth
- Multi-registry support with authentication
- Proper error handling and logging

## Project Dependencies

From `shard.yml`:

- `docr` - Docker API client
- `docopt` + `docopt-config` - Command-line parsing
- `kemal` - Web framework
- `baked_file_system` - Embedded file system for static assets
- `baked_file_handler` - Handler for baked files in Kemal
- `progress` - Progress bars for CLI operations

## Crystal Version

This project requires Crystal >= 1.16.3 (CI runs on `crystal: latest`; developed with Crystal 1.21).

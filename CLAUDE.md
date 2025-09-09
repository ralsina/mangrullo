# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Crystal Language project called "mangrullo" - a Docker container update automation tool similar to Watchtower. The project is functional and includes container monitoring, update detection, container recreation, and filtering capabilities. It follows standard Crystal conventions with comprehensive tests and a modular architecture.

## Development Commands

### Building and Running
- `crystal build src/mangrullo.cr` - Compile the CLI
- `crystal build src/web.cr` - Compile the web interface
- `crystal run src/mangrullo.cr` - Run the CLI
- `crystal run src/web.cr` - Run the web interface
- `crystal tool format` - Format code according to Crystal style guidelines

### Testing
- `crystal spec` - Run all tests (56 examples)
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
- `src/web.cr` - Web interface entry point
- `src/web_server.cr` - Kemal web server implementation
- `src/web_views.cr` - Web interface templates
- `src/error_handling.cr` - Centralized error management

### Configuration
- `shard.yml` - Project dependencies and build targets
- `spec/mangrullo_spec.cr` - Comprehensive test suite (56 examples)
- `spec/spec_helper.cr` - Test configuration

## Key Features Implemented

- **Container Monitoring**: Automatically detects running Docker containers
- **Update Detection**: Compares local and remote image versions/digests
- **Container Filtering**: Check specific containers by name with flexible matching
- **Container Recreation**: Properly recreates containers with new images (like Watchtower)
- **Multi-Registry Support**: Docker Hub, GHCR, lscr.io (with proper mapping)
- **Semantic Versioning**: Intelligent version comparison with major upgrade control
- **Dry Run Mode**: Test updates without making changes
- **Web Interface**: Optional web-based monitoring and management
- **Comprehensive Testing**: Unit tests for all major functionality

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
- Container recreation that properly updates containers (not just restart)
- Flexible container name matching (handles both "name" and "/name")
- Comprehensive test suite (56 examples, 0 failures)
- Web interface framework in place
- Multi-registry support with authentication
- Proper error handling and logging

## Dependencies

From `shard.yml`:
- `docr` - Docker API client
- `docopt` - Command-line parsing
- `kemal` - Web framework
- `kilt` - Template engine

## Crystal Version

This project requires Crystal >= 1.16.3 (developed with Crystal 1.17.1).
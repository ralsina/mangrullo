# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Mangrullo is a Docker container update automation tool written in Crystal, similar to Watchtower. It monitors running Docker containers, checks for image updates, and automatically recreates containers with new images while preserving their configuration. The project includes both a CLI tool and a web-based management interface.

## Build and Development Commands

### Build

```bash
shards build                    # Build both mangrullo and mangrillo-web binaries
shards build mangrullo          # Build CLI only
shards build mangrullo-web      # Build web interface only
make build                      # Same as shards build
make all                        # Run lint, build, and test
```

**Important:** This project has TWO binaries. When making changes, verify BOTH binaries build successfully.

### Test

```bash
crystal spec                    # Run all tests
crystal spec spec/mangrullo_spec.cr  # Run specific test file
crystal spec --verbose          # Run tests with detailed output
make test                       # Run all tests
```

### Lint and Format

```bash
ameba                           # Run Crystal linter
ameba --fix                     # Auto-fix linting issues
make lint                       # Run JavaScript syntax checker
make lint-fix                   # Fix JavaScript linting
crystal tool format             # Format Crystal code
```

### Dependency Management

```bash
shards install                  # Install/update dependencies
shards check                    # Check shard.yml is valid
```

## Architecture

### High-Level Structure

The codebase follows a modular architecture with clear separation of concerns:

- **CLI Module** (`cli.cr`) - Main application entry point using Docopt for CLI parsing
- **Config Module** (`config.cr`) - Configuration management with environment variable support
- **Docker Client** (`docker_client.cr`) - Docker API wrapper with global mutex for thread safety
- **Image Checker** (`image_checker.cr`) - Update detection logic with multi-registry support
- **Update Manager** (`update_manager.cr`) - Orchestrates the update workflow
- **State Manager** (`state_manager.cr`) - Singleton for background update coordination (web mode)
- **Container State** (`container_state.cr`) - Thread-safe shared state for web interface
- **Web Server** (`web_server.cr`) - Kemal-based REST API
- **Web Views** (`web_views.cr`) - ECR templates for the web UI

### Key Architectural Patterns

1. **Singleton Pattern:** StateManager and ContainerState use singleton pattern for web interface
2. **Global Mutex:** DockerClient uses a global mutex to prevent concurrent Docker API access
3. **Dependency Injection:** DockerClient is injected into ImageChecker and UpdateManager
4. **Fiber-based Concurrency:** Background fibers for periodic updates in web mode
5. **Module Namespace:** All code lives under the `Mangrullo` module

### Data Flow

**CLI Mode:**
```
CLI.new → UpdateManager → DockerClient + ImageChecker → Container recreation
```

**Web Mode:**
```
Kemal Server → WebServer routes → StateManager → ContainerState (background fiber updates)
```

### External Dependencies (lib/)

Code in `lib/` consists of external Crystal shards and **should not be modified**:
- ameba, baked_file_handler, baked_file_system, crystar, docopt, docr, exception_page, kemal, progress, radix

## Code Style Guidelines

- **Indentation:** 2 spaces
- **Naming:** CamelCase for modules/classes, UPPER_SNAKE_CASE for constants, snake_case for methods
- **nil handling:** Avoid `not_nil!` - use proper nilable type handling
- **Conditionals:** Prefer `unless` over `if !` for negative conditions
- **Block parameters:** Use descriptive names instead of single letters
- **Formatting:** Always run `crystal tool format` before committing

## Configuration Options

The application supports CLI arguments, environment variables, and YAML config files (via `docopt-config`).

### Precedence Order
1. CLI arguments (highest priority)
2. Environment variables (prefix: `MANGRULLO_`)
3. Config file (YAML, optional)
4. Docopt defaults (lowest priority)

### Options

- `--interval=<seconds>` / `MANGRULLO_INTERVAL` / `interval` - Check interval (default: 300s)
- `--allow-major` / `MANGRULLO_ALLOW_MAJOR` / `allow_major` - Allow major version upgrades
- `--socket=<path>` / `MANGRULLO_SOCKET` / `socket` - Docker socket path (default: /var/run/docker.sock)
- `--log-level=<level>` / `MANGRULLO_LOG_LEVEL` / `log_level` - Logging level (debug, info, warn, error)
- `--once` / `MANGRULLO_RUN_ONCE` / `run_once` - Run once and exit
- `--dry-run` / `MANGRULLO_DRY_RUN` / `dry_run` - Show what would be updated without changes
- `<container-name>...` - Specific containers to check

### Config File Example

Create a `config.yml` file:

```yaml
# Mangrullo configuration
interval: 600
allow_major: false
socket: "/var/run/docker.sock"
log_level: "info"
run_once: false
dry_run: false
```

## Special Implementation Details

### Multi-Registry Support

- Docker Hub (default)
- GitHub Container Registry (ghcr.io)
- lscr.io → ghcr.io automatic mapping (LinuxServer containers)

### Update Detection Strategy

- For 'latest' tags: Digest-based comparison (local vs remote registry)
- For versioned tags: Semantic version comparison
- Registry authentication with token caching

### Container Recreation

Container updates follow this sequence:
1. Capture container config via `docker inspect`
2. Stop container
3. Remove container
4. Create with new image (preserving config)
5. Start container

This ensures the container is properly recreated with the new image, not just restarted.

### Thread Safety

- Global mutex (`DOCKER_MUTEX`) protects all Docker API operations
- Fiber-based concurrency for background updates
- Thread-safe container state management in web mode

### Error Handling

- Docker API operations include retry logic (3 attempts with exponential backoff)
- Centralized error handling via `error_handling.cr`
- Graceful degradation on failures

## Testing

The project uses Crystal's built-in `spec` framework (rspec-like).

- Test helper: `spec/spec_helper.cr` (includes `TestHelper` module with mock creation utilities)
- All tests set log level to `:none` to avoid output clutter
- Comprehensive coverage: 155+ examples across multiple spec files

## Pre-commit Hook

The repository includes a pre-commit hook (`hooks/pre-commit`) that must be manually installed:

```bash
cp hooks/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

The hook runs:
1. `crystal spec` - All tests must pass
2. `ameba` - Code must pass linting

If the hook fails, fix the issues and retry the commit. Do NOT amend the previous commit - create a new one.

## CI/CD

GitHub Actions workflow (`.github/workflows/ci.yml`) runs on every push/PR:
- Crystal installation
- Dependency installation
- Format check (`crystal tool format --check`)
- Tests (`crystal spec`)
- Linting (`ameba`)

## Known Issues and Workarounds

### DOCR Library Issues

The docr library has issues with missing optional fields in Docker API responses. Workarounds are implemented in `src/docr_workarounds.cr` which monkey-patches affected types:
- `NetworkSettings` - Missing `Bridge`, `SandboxID`, and other network fields
- `Image` - Missing `Comment`, `RepoTags`, `RepoDigests`, `Config`, `Metadata`
- `ContainerSummary` - Missing `Names`, `Labels`, `Command`, `State`, `Status`
- `ImageSummary` - Missing `ParentId`, `SharedSize`, `Containers`

The workarounds file is automatically required by `docker_client.cr`. See `DOCR_BUG_NOTES.md` for details.

### Linter Exclusions

- Cyclomatic complexity excluded for `web_server.cr` and `update_manager.cr` (complex methods)
- `RedundantBegin` rule disabled for `image_checker.cr` (needed for exception handling)
- `web_views.cr` excluded from formatting due to JavaScript regex literals in HTML templates

### JavaScript in Templates

The web views (`web_views.cr`) contain embedded JavaScript and CSS. When modifying these files:
- Be careful with regex literals that Crystal's formatter may misinterpret
- Use `node check-syntax.js` to validate JavaScript syntax
- Use `npm run lint:fix` to auto-fix JavaScript linting issues

## Static Assets

Static files (CSS, JS, images) are embedded into the binary using BakedFileSystem:
- Generated by the `BakedFileSystem` macro in `static_assets.cr`
- Compiled into the binary for easy deployment
- To regenerate: Modify files in `public/` and rebuild

## Crystal Version

Requires Crystal >= 1.16.3 (developed with Crystal 1.17.1).

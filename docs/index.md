# Mangrullo

[![Crystal CI](https://github.com/ralsina/mangrullo/workflows/Crystal%20CI/badge.svg)](https://github.com/ralsina/mangrullo/actions)
[![GitHub release](https://img.shields.io/github/v/release/ralsina/mangrullo)](https://github.com/ralsina/mangrullo/releases)
[![License](https://img.shields.io/github/license/ralsina/mangrullo)](https://github.com/ralsina/mangrullo/blob/main/LICENSE)

Mangrullo is a Docker container update automation tool written in Crystal. It monitors running Docker containers and automatically updates them to newer image versions, similar to Watchtower but with a focus on simplicity and reliability.

## Installation from Source

1. Clone the repository:

   ```bash
   git clone https://github.com/ralsina/mangrillo.git
   cd mangrullo
   ```

1. Install dependencies:

   ```bash
   shards install
   ```

1. Build the project:

   ```bash
   shards build
   ```

1. Install the binary (optional):

   ```bash
   cp bin/mangrullo /usr/local/bin/
   ```

## Features

- 🔍 **Automatic Monitoring**: Continuously monitors running Docker containers for image updates
- 📦 **Semantic Versioning**: Intelligent version comparison with support for major/minor/patch updates
- 🛡️ **Safe Updates**: Optional control over major version upgrades to prevent breaking changes
- 🏃 **Dry Run Mode**: Test what would be updated without making actual changes
- 📊 **Detailed Logging**: Comprehensive logging with configurable log levels
- 🔄 **Flexible Scheduling**: Run once or set up continuous monitoring with custom intervals
- 🔧 **Easy Configuration**: Simple command-line interface with sensible defaults
- 🎯 **Container Filtering**: Check specific containers by name instead of all containers
- 🔄 **Container Recreation**: Properly recreates containers with new images (like Watchtower)
- 🌐 **Multi-Registry Support**: Works with Docker Hub, GitHub Container Registry, and more

## Installation

### From Source

1. Install Crystal (>= 1.16.3) following the [official installation guide](https://crystal-lang.org/installation/)
2. Clone the repository:

   ```bash
   git clone https://github.com/ralsina/mangrullo.git
   cd mangrullo
   ```

3. Install dependencies:

   ```bash
   shards install
   ```

4. Build the project:

   ```bash
   shards build
   ```

5. Install the binary (optional):

   ```bash
   cp bin/mangrullo /usr/local/bin/
   ```

### Pre-built Binaries

Pre-built static binaries are available for multiple architectures in the `bin/` directory:

- `mangrullo-static-linux-amd64` - Linux x86_64
- `mangrullo-static-linux-arm64` - Linux ARM64
- `mangrullo-web-static-linux-amd64` - Web interface for Linux x86_64
- `mangrullo-web-static-linux-arm64` - Web interface for Linux ARM64

These binaries include all dependencies and don't require Crystal to be installed on the target system.

### Using Docker

```bash
docker run -d \
  --name mangrullo \
  -v /var/run/docker.sock:/var/run/docker.sock \
  ralsina/mangrullo:latest
```

## Usage

### Basic Usage

Monitor running containers and update them when new images are available:

```bash
# Run once and exit
mangrullo --once

# Run continuously with default 6-hour intervals
mangrullo

# Allow major version upgrades
mangrullo --allow-major

# Dry run to see what would be updated
mangrullo --dry-run
```

### Command Line Options

```text
Usage:
  mangrullo [--interval=<seconds>] [--allow-major] [--socket=<path>]
           [--log-level=<level>] [--once] [--dry-run] [--help] [--version]

Options:
  --interval=<seconds>   Check interval in seconds [default: 21600]
  --allow-major          Allow major version upgrades
  --socket=<path>        Docker socket path [default: /var/run/docker.sock]
  --log-level=<level>    Log level (debug, info, warn, error) [default: info]
  --once                 Run once and exit
  --dry-run              Show what would be updated without actually updating
  --help                 Show this help message
  --version              Show version information

Arguments:
  <container-name>       Specific container names to check (if not specified, checks all containers)
```

**Note**: The default check interval is 21600 seconds (6 hours) to avoid Docker Hub registry rate limiting.

### Examples

**Check for updates once:**

```bash
mangrullo --once
```

**Monitor every 10 minutes with debug logging:**

```bash
mangrullo --interval=600 --log-level=debug
```

**Test updates including major versions:**

```bash
mangrullo --dry-run --allow-major
```

**Check only specific containers:**

```bash
mangrullo --once flatnotes atuin radicale
```

**Check specific containers (with or without leading slash):**

```bash
mangrullo --once /flatnotes atuin /radicale
```

**Use custom Docker socket:**

```bash
mangrullo --socket=/path/to/docker.sock
```

## Web Interface

Mangrullo includes a fully-featured web interface that provides a modern dashboard for monitoring and managing Docker container updates.

### Starting the Web Interface

```bash
# Build and run the web interface
shards build mangrullo-web
./bin/mangrullo-web
```

The web interface starts on `http://localhost:3000` and provides:

- **Dashboard**: Real-time overview of all containers and their update status
- **Auto-refresh**: Automatic updates every 30 seconds
- **Container Management**: Check for updates and update individual containers
- **Bulk Operations**: Update multiple containers at once with dry-run support
- **Dry Run Modal**: Comprehensive results display showing what would be updated
- **Modern UI**: Clean, responsive design using Pico.css with Chivo fonts
- **Brand Identity**: Custom cell tower icon and favicon integration

### Key Features

- **Auto-refresh Dashboard**: Container status automatically updates without manual refresh
- **Embedded Static Assets**: All CSS, JavaScript, and images are baked into the binary for easy deployment
- **Responsive Design**: Works on desktop and mobile devices with proper scaling
- **Real-time Status**: Live indicators for update checks and container operations
- **Dry Run Support**: Comprehensive dry run results with detailed tables showing update status
- **Bulk Update Operations**: Update all containers with major version control and dry run options
- **Custom Branding**: Cell tower icon throughout interface with 50% larger text
- **Favicon Support**: Both SVG and ICO favicons with cell tower branding

### Web Interface Architecture

The web interface uses:

- **Kemal**: Fast web framework for Crystal
- **Baked File System**: Static assets embedded in the binary for zero-dependency deployment
- **State Manager**: Shared state between web requests and background operations
- **Auto-refresh**: JavaScript-based periodic updates every 30 seconds
- **Google Fonts**: Chivo and Chivo Mono fonts for enhanced typography
- **Material Icons**: Google Material Icons for consistent iconography

## Configuration

Mangrillo supports flexible configuration through multiple methods with a clear precedence order:

### Precedence (highest to lowest)

1. **Command-line arguments** - Always take precedence
2. **Environment variables** - Used when CLI argument is not provided
3. **Configuration file** - YAML file for persistent settings
4. **Default values** - Built-in defaults as last resort

### Command-Line Options

```bash
mangrullo [--interval=<seconds>] [--allow-major] [--socket=<path>]
          [--log-level=<level>] [--once] [--dry-run] [<container-name>...]
```

| Option | Description | Default |
|--------|-------------|---------|
| `--interval=<seconds>` | Check interval in seconds | `300` |
| `--allow-major` | Allow major version upgrades | `false` |
| `--socket=<path>` | Docker socket path | `/var/run/docker.sock` |
| `--log-level=<level>` | Logging level (debug, info, warn, error) | `info` |
| `--once` | Run once and exit | `false` |
| `--dry-run` | Show what would be updated without changes | `false` |
| `<container-name>...` | Specific containers to check | all containers |

### Environment Variables

All options can be set via environment variables with the `MANGRULLO_` prefix:

| Variable | Description | Example |
|----------|-------------|---------|
| `MANGRULLO_INTERVAL` | Check interval | `MANGRULLO_INTERVAL=600` |
| `MANGRULLO_ALLOW_MAJOR` | Allow major upgrades | `MANGRULLO_ALLOW_MAJOR=true` |
| `MANGRULLO_SOCKET` | Docker socket path | `MANGRULLO_SOCKET=/var/run/docker.sock` |
| `MANGRULLO_LOG_LEVEL` | Logging level | `MANGRULLO_LOG_LEVEL=debug` |
| `MANGRULLO_RUN_ONCE` | Run once and exit | `MANGRULLO_RUN_ONCE=true` |
| `MANGRULLO_DRY_RUN` | Dry run mode | `MANGRULLO_DRY_RUN=true` |

### Configuration File

You can also use a YAML configuration file (`config.yml`):

```yaml
# Mangrullo configuration
interval: 600
allow_major: false
socket: "/var/run/docker.sock"
log_level: "info"
run_once: false
dry_run: false
```

### Docker Socket

By default, Mangrullo connects to the Docker daemon at `/var/run/docker.sock`. You can specify a different path using the `--socket` option or `MANGRULLO_SOCKET` environment variable.

### Version Handling

Mangrullo uses semantic versioning to determine when updates are available:

- **Patch updates** (1.0.0 → 1.0.1): Always applied by default
- **Minor updates** (1.0.0 → 1.1.0): Always applied by default
- **Major updates** (1.0.0 → 2.0.0): Only applied when `--allow-major` is specified

### Image Support

Mangrullo works with:

- Standard image tags (nginx:1.2.3)
- Registry prefixes (docker.io/library/nginx:1.2.3)
- SHA256 digests (skipped for version comparison)
- Latest tags (always check for updates)
- Multiple registries:
  - Docker Hub (registry-1.docker.io)
  - GitHub Container Registry (ghcr.io)
  - LinuxServer.io (lscr.io - maps to ghcr.io/linuxserver/)
  - Other standard Docker registry v2 implementations

## Development

### Prerequisites

- Crystal >= 1.16.3
- Docker (for testing)
- Git

### Setup

1. Clone the repository:

   ```bash
   git clone https://github.com/ralsina/mangrullo.git
   cd mangrullo
   ```

2. Install dependencies:

   ```bash
   shards install
   ```

3. Run tests:

   ```bash
   crystal spec
   ```

4. Build the project:

   ```bash
   shards build
   ```

### Running Tests

The project includes comprehensive unit tests:

```bash
# Run all tests
crystal spec

# Run specific test file
crystal spec spec/mangrullo_spec.cr

# Run with verbose output
crystal spec --verbose
```

The test suite covers:

- Container name matching and filtering
- Registry mapping and authentication
- Container recreation logic
- Version parsing and comparison
- Image update detection algorithms

### Code Style

- Follow Crystal language conventions
- Use 2-space indentation
- Module names are CamelCase
- Constants are UPPER_SNAKE_CASE
- Method names are snake_case

Format code with:

```bash
crystal tool format
```

## Architecture

Mangrullo is built with a modular architecture:

- **Types** (`src/types.cr`): Core data structures and version comparison logic
- **Docker Client** (`src/docker_client.cr`): Docker API wrapper and container recreation
- **Image Checker** (`src/image_checker.cr`): Version checking and update detection
- **Update Manager** (`src/update_manager.cr`): Coordinates the update process with container filtering
- **Configuration** (`src/config.cr`): Command-line argument parsing
- **CLI** (`src/cli.cr`): Main command-line interface
- **Web Server** (`src/web_server_baked.cr`): Web interface with baked static assets (optional)
- **Web Views** (`src/web_views.cr`): Web interface templates with auto-refresh
- **Static Assets** (`src/static_assets.cr`): Embedded CSS, JavaScript, and images
- **State Manager** (`src/state_manager.cr`): Shared state management for web interface
- **Error Handling** (`src/error_handling.cr`): Centralized error management

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request. For major changes, please open an issue first to discuss what you would like to change.

### Development Workflow

1. Fork the repository
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Make your changes
4. Add tests for new functionality
5. Ensure all tests pass (`crystal spec`)
6. Format your code (`crystal tool format`)
7. Commit your changes (`git commit -am 'Add some feature'`)
8. Push to the branch (`git push origin my-new-feature`)
9. Create a new Pull Request

### Reporting Issues

Please use the [GitHub Issues](https://github.com/ralsina/mangrullo/issues) page to report bugs or request features.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Inspired by [Watchtower](https://github.com/containrrr/watchtower)
- Built with [Crystal](https://crystal-lang.org/)
- Uses the [docr](https://github.com/marghidanu/docr) Docker client library
- Uses [docopt.cr](https://github.com/ralsina/docopt.cr) for command-line parsing

## Changelog

### v0.1.0

- Initial release
- Basic container monitoring and update functionality
- Semantic version comparison
- Major version upgrade control
- Dry run mode
- Comprehensive unit tests
- Command-line interface
- Container-specific filtering (check only specified containers)
- Container recreation (properly updates containers with new images)
- Multi-registry support (Docker Hub, GHCR, lscr.io)
- Web interface framework (Kemal-based)
- Flexible container name matching (handles both "name" and "/name")
- Comprehensive error handling and logging

### Recent Updates

- **Comprehensive Web Interface**: Full-featured dashboard with auto-refresh and bulk operations
- **Dry Run Modal**: Detailed results display showing what would be updated with CLI-like output
- **Custom Branding**: Cell tower icons throughout interface with favicon support
- **Typography Enhancement**: Chivo and Chivo Mono Google Fonts integration
- **Bulk Update Operations**: Update multiple containers with dry run and major version controls
- **Button State Management**: Proper onclick handling to prevent double-clicks during operations
- **Critical JSON Fix**: Fixed dry run checkbox being ignored due to form vs JSON parameter parsing
- **Embedded Static Assets**: All web interface assets (CSS, JS, images) baked into binary
- **Auto-refresh Dashboard**: Web interface automatically updates every 30 seconds
- **Rate Limiting Protection**: Default 6-hour check interval to avoid Docker Hub rate limits
- **Multi-architecture Builds**: Static binaries available for Linux AMD64 and ARM64
- **CI Workflow Improvements**: Added Ameba as development dependency for proper linting

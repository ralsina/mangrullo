# Mangrullo

[![Crystal CI](https://github.com/ralsina/mangrullo/workflows/Cystal%20CI/badge.svg)](https://github.com/ralsina/mangrullo/actions)
[![GitHub release](https://img.shields.io/github/v/release/ralsina/mangrullo)](https://github.com/ralsina/mangrullo/releases)
[![License](https://img.shields.io/github/license/ralsina/mangrullo)](https://github.com/ralsina/mangrullo/blob/main/LICENSE)

Mangrullo is a Docker container update automation tool written in Crystal. It monitors running Docker containers and automatically updates them to newer image versions, similar to Watchtower but with a focus on simplicity and reliability.

## Features

- 🔍 **Automatic Monitoring**: Continuously monitors running Docker containers for image updates
- 📦 **Semantic Versioning**: Intelligent version comparison with support for major/minor/patch updates
- 🛡️ **Safe Updates**: Optional control over major version upgrades to prevent breaking changes
- 🏃 **Dry Run Mode**: Test what would be updated without making actual changes
- 📊 **Detailed Logging**: Comprehensive logging with configurable log levels
- 🔄 **Flexible Scheduling**: Run once or set up continuous monitoring with custom intervals
- 🔧 **Easy Configuration**: Simple command-line interface with sensible defaults

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

# Run continuously with 5-minute intervals
mangrullo --interval=300

# Allow major version upgrades
mangrullo --allow-major

# Dry run to see what would be updated
mangrullo --dry-run
```

### Command Line Options

```
Usage:
  mangrullo [--interval=<seconds>] [--allow-major] [--socket=<path>] 
           [--log-level=<level>] [--once] [--dry-run] [--help] [--version]

Options:
  --interval=<seconds>   Check interval in seconds [default: 300]
  --allow-major          Allow major version upgrades
  --socket=<path>        Docker socket path [default: /var/run/docker.sock]
  --log-level=<level>    Log level (debug, info, warn, error) [default: info]
  --once                 Run once and exit
  --dry-run              Show what would be updated without actually updating
  --help                 Show this help message
  --version              Show version information
```

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

**Use custom Docker socket:**
```bash
mangrullo --socket=/path/to/docker.sock
```

## Configuration

Mangrullo is configured primarily through command-line arguments. There are no configuration files or environment variables to manage.

### Docker Socket

By default, Mangrullo connects to the Docker daemon at `/var/run/docker.sock`. You can specify a different path using the `--socket` option.

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
crystal spec spec/version_spec.cr

# Run with verbose output
crystal spec --verbose
```

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
- **Docker Client** (`src/docker_client.cr`): Docker API wrapper
- **Image Checker** (`src/image_checker.cr`): Version checking and update detection
- **Update Manager** (`src/update_manager.cr`): Coordinates the update process
- **Configuration** (`src/config.cr`): Command-line argument parsing
- **CLI** (`src/cli.cr`): Main command-line interface

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

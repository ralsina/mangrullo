#!/bin/bash
set -e

# Function to show usage
show_usage() {
    cat << EOF
Mangrullo - Docker Container Update Manager

Usage:
    docker run <image> [COMMAND] [OPTIONS]

Commands:
    daemon              Run in daemon mode (default)
    web                 Run web interface only
    check               Run single update check
    dry-run             Show what would be updated
    help                Show this help

Environment Variables:
    MANGRULLO_DOCKER_SOCKET     Docker socket path (default: /var/run/docker.sock)
    MANGRULLO_LOG_LEVEL         Log level: debug, info, warn, error (default: info)
    MANGRULLO_INTERVAL          Check interval in seconds (default: 3600)
    MANGRULLO_WEB_PORT          Web interface port (default: 3000)
    MANGRULLO_WEB_HOST          Web interface host (default: 0.0.0.0)
    MANGRULLO_ALLOW_MAJOR       Allow major version upgrades (default: false)

Examples:
    # Run as daemon
    docker run -d --name mangrullo \
        -v /var/run/docker.sock:/var/run/docker.sock \
        mangrullo daemon

    # Run web interface
    docker run -d --name mangrullo-web \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -p 3000:3000 \
        mangrullo web

    # Single check
    docker run --rm \
        -v /var/run/docker.sock:/var/run/docker.sock \
        mangrullo check

    # Dry run
    docker run --rm \
        -v /var/run/docker.sock:/var/run/docker.sock \
        mangrullo dry-run
EOF
}

# Handle command
case "${1:-daemon}" in
    "daemon")
        echo "Starting Mangrullo in daemon mode..."
        exec mangrullo --log-level="${MANGRULLO_LOG_LEVEL:-info}" \
             --interval="${MANGRULLO_INTERVAL:-3600}" \
             --socket="${MANGRULLO_DOCKER_SOCKET}" \
             ${MANGRULLO_ALLOW_MAJOR:+--allow-major}
        ;;
    "web")
        echo "Starting Mangrullo web interface..."
        exec mangrullo-web --port="${MANGRULLO_WEB_PORT:-3000}" \
             --host="${MANGRULLO_WEB_HOST:-0.0.0.0}"
        ;;
    "check")
        echo "Running single update check..."
        exec mangrullo --log-level="${MANGRULLO_LOG_LEVEL:-info}" \
             --socket="${MANGRULLO_DOCKER_SOCKET}" \
             ${MANGRULLO_ALLOW_MAJOR:+--allow-major} \
             --once
        ;;
    "dry-run")
        echo "Running dry run..."
        exec mangrullo --log-level="${MANGRULLO_LOG_LEVEL:-info}" \
             --socket="${MANGRULLO_DOCKER_SOCKET}" \
             --dry-run
        ;;
    "help"|"-h"|"--help")
        show_usage
        exit 0
        ;;
    *)
        echo "Unknown command: $1"
        echo ""
        show_usage
        exit 1
        ;;
esac
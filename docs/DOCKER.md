# Docker Deployment Guide

This guide explains how to deploy Mangrullo using Docker containers.

## Quick Start

The official images are published on GitHub Container Registry:
`ghcr.io/ralsina/mangrullo:latest` (multi-architecture: amd64 + arm64).

The image ships an entrypoint that understands the commands `daemon` (default), `web`, `check`, `dry-run` and `help`.

### Option 1: One-shot Mode

Run a single update check:

```bash
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  ghcr.io/ralsina/mangrullo:latest check
```

### Option 2: Daemon Mode

Run Mangrullo as a background daemon that periodically checks for updates:

```bash
docker run -d \
  --name mangrullo \
  -v /var/run/docker.sock:/var/run/docker.sock \
  ghcr.io/ralsina/mangrullo:latest
```

The daemon checks every `MANGRULLO_INTERVAL` seconds (entrypoint default: 3600).

### Option 3: Dry Run Mode

See what would be updated without making changes:

```bash
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  ghcr.io/ralsina/mangrullo:latest dry-run
```

### Option 4: Check Specific Containers

The entrypoint commands don't take container names; bypass the entrypoint to
filter by name:

```bash
docker run --rm \
  --entrypoint mangrullo \
  -v /var/run/docker.sock:/var/run/docker.sock \
  ghcr.io/ralsina/mangrullo:latest \
  --once flatnotes atuin
```

## Docker Compose

Use the provided `docker-compose.yml` for easier deployment:

### Start Mangrullo

```bash
docker-compose up -d
```

### Stop Mangrullo

```bash
docker-compose down
```

### View Logs

```bash
docker-compose logs -f
```

## Configuration

### Environment Variables

All configuration options can be set via environment variables with the `MANGRULLO_` prefix:

| Variable | Description | Default |
|----------|-------------|---------|
| `MANGRULLO_INTERVAL` | Check interval in seconds | `3600` (entrypoint) |
| `MANGRULLO_ALLOW_MAJOR` | Allow major version upgrades | `false` |
| `MANGRULLO_SOCKET` | Docker socket path | `/var/run/docker.sock` |
| `MANGRULLO_LOG_LEVEL` | Log level (debug, info, warn, error) | `info` |
| `MANGRULLO_RUN_ONCE` | Run once and exit | `false` |
| `MANGRULLO_DRY_RUN` | Show what would be updated without changes | `false` |

Web mode honors these additional variables (set them for the `web` service):

| Variable | Description | Default |
|----------|-------------|---------|
| `MANGRULLO_WEB_PORT` | Web interface port | `3000` |
| `MANGRULLO_WEB_HOST` | Web interface bind address | `0.0.0.0` |
| `MANGRULLO_WEB_USER` | HTTP Basic auth user (optional) | unset |
| `MANGRULLO_WEB_PASSWORD` | HTTP Basic auth password (optional) | unset |

**Note:** Setting both `MANGRULLO_WEB_USER` and `MANGRULLO_WEB_PASSWORD` enables
HTTP Basic authentication on every route except `/health` (so Docker health
checks keep working). With either unset the UI is open.

**Note:** The old environment variable `MANGRULLO_DOCKER_SOCKET` has been renamed to `MANGRULLO_SOCKET` for consistency.

### Configuration File

YAML configuration file support is *not currently enabled*: the plumbing
exists (via `docopt-config`) but no CLI flag passes a config file path, and
`--config=/config.yml` is not a valid option. Use environment variables
instead.

### Example with Custom Configuration

```bash
docker run -d \
  --name mangrullo \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -e MANGRULLO_LOG_LEVEL=debug \
  -e MANGRULLO_INTERVAL=1800 \
  -e MANGRULLO_ALLOW_MAJOR=true \
  ghcr.io/ralsina/mangrullo:latest daemon
```

## Building the Image

Build the Docker image from source:

```bash
docker build -t mangrullo .
```

Build for a specific platform:

```bash
docker build -t mangrullo --platform linux/amd64 .
docker build -t mangrullo --platform linux/arm64 .
```

## Security Considerations

### Docker Socket Access

Mangrullo needs access to the Docker socket to manage containers. This is done with:

```bash
-v /var/run/docker.sock:/var/run/docker.sock
```

Note: Mangrullo needs write access to the Docker socket to recreate containers. The `:ro` flag cannot be used as it would prevent container operations. If you want to restrict access further, consider:

1. **Using a Docker socket proxy** that filters allowed operations
2. **Running Mangrullo in a separate Docker network** with limited access
3. **Using Docker's socket activation** with proper permissions

### Non-root User

The Docker image runs Mangrullo as a non-root user (UID 1000) for improved security.

## Monitoring

### Logs

View container logs:

```bash
docker logs mangrullo
docker logs -f mangrullo  # Follow logs
```

### Health Checks

The image defines a Docker `HEALTHCHECK` that curls the web endpoint
(`http://localhost:${MANGRULLO_WEB_PORT:-3000}/`). That means:

- **Web mode** (`command: web`): the container reports `healthy` while the UI answers.
- **Daemon mode**: there is no HTTP server, so the built-in healthcheck reports
  `unhealthy` even though the daemon works. Check the daemon with:

```bash
docker inspect mangrullo --format='{{.State.Status}}'
docker logs -f mangrullo
```

## Production Deployment

### Using Docker Swarm

```yaml
version: '3.8'
services:
  mangrullo:
    image: mangrullo:latest
    deploy:
      mode: replicated
      replicas: 1
      restart_policy:
        condition: on-failure
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    environment:
      - MANGRULLO_LOG_LEVEL=info
      - MANGRULLO_INTERVAL=3600
    networks:
      - mangrullo-network

networks:
  mangrullo-network:
    driver: overlay
```

### Using Kubernetes

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mangrullo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mangrullo
  template:
    metadata:
      labels:
        app: mangrullo
    spec:
      containers:
      - name: mangrullo
        image: mangrullo:latest
        env:
        - name: MANGRULLO_LOG_LEVEL
          value: "info"
        - name: MANGRULLO_INTERVAL
          value: "3600"
        volumeMounts:
        - name: docker-socket
          mountPath: /var/run/docker.sock
          readOnly: true
      volumes:
      - name: docker-socket
        hostPath:
          path: /var/run/docker.sock
```

## Troubleshooting

### Permission Denied

If you get permission denied errors:

```bash
# Add user to docker group on host
sudo usermod -aG docker $USER

# Or run with elevated privileges
docker run --privileged ...
```

### Connection Issues

If Mangrullo can't connect to Docker:

1. Verify Docker is running: `docker ps`
2. Check socket permissions: `ls -la /var/run/docker.sock`
3. Ensure the socket is mounted correctly

## Advanced Usage

### Custom Dockerfile

For custom builds, create a `.dockerignore` file:

```text
.git
.github
.spec
lib/
bin/
*.log
.DS_Store
```

### Multi-architecture Builds

Build for multiple architectures:

```bash
docker buildx build --platform linux/amd64,linux/arm64 -t mangrullo:latest .
```

### Private Registry

Push to a private registry:

```bash
docker tag mangrullo:latest my-registry.com/mangrullo:latest
docker push my-registry.com/mangrullo:latest
```

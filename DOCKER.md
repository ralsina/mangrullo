# Docker Deployment Guide

This guide explains how to deploy Mangrullo using Docker containers.

## Quick Start

### Option 1: Daemon Mode (Recommended)
Run Mangrullo as a background daemon that periodically checks for updates:

```bash
docker run -d \
  --name mangrullo \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  mangrullo daemon
```

### Option 2: Web Interface Mode
Run Mangrullo with a web interface for monitoring:

```bash
docker run -d \
  --name mangrullo-web \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -p 3000:3000 \
  mangrullo web
```

### Option 3: One-shot Mode
Run a single update check:

```bash
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  mangrullo check
```

### Option 4: Dry Run Mode
See what would be updated without making changes:

```bash
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  mangrullo dry-run
```

## Docker Compose

Use the provided `docker-compose.yml` for easier deployment:

### Daemon Mode Only
```bash
docker-compose --profile daemon up -d
```

### Web Interface Only
```bash
docker-compose --profile web up -d
```

### Combined Mode (Daemon + Web)
```bash
docker-compose --profile combined up -d
```

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `MANGRULLO_DOCKER_SOCKET` | Docker socket path | `/var/run/docker.sock` |
| `MANGRULLO_LOG_LEVEL` | Log level (debug, info, warn, error) | `info` |
| `MANGRULLO_INTERVAL` | Check interval in seconds | `3600` |
| `MANGRULLO_WEB_PORT` | Web interface port | `3000` |
| `MANGRULLO_WEB_HOST` | Web interface host | `0.0.0.0` |
| `MANGRULLO_ALLOW_MAJOR` | Allow major version upgrades | `false` |

### Example with Custom Configuration

```bash
docker run -d \
  --name mangrullo \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -e MANGRULLO_LOG_LEVEL=debug \
  -e MANGRULLO_INTERVAL=1800 \
  -e MANGRULLO_ALLOW_MAJOR=true \
  mangrullo daemon
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
-v /var/run/docker.sock:/var/run/docker.sock:ro
```

The `:ro` flag makes the socket read-only, but Mangrullo still needs write access to restart containers. If you want to restrict access further, consider:

1. **Using a Docker socket proxy** that filters allowed operations
2. **Running Mangrullo in a separate Docker network** with limited access
3. **Using Docker's socket activation** with proper permissions

### Non-root User
The Docker image runs Mangrullo as a non-root user (UID 1000) for improved security.

### Network Isolation
When using the web interface, consider binding to a specific interface instead of `0.0.0.0`:

```bash
-e MANGRULLO_WEB_HOST=127.0.0.1
```

## Monitoring

### Logs
View container logs:

```bash
docker logs mangrullo
docker logs -f mangrullo  # Follow logs
```

### Health Checks
The web interface includes a health check:

```bash
docker inspect mangrullo-web --format='{{.State.Health.Status}}'
```

### Metrics
The web interface provides metrics at `/metrics` endpoint (if available in your version).

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

### Web Interface Not Accessible
If the web interface is not accessible:
1. Check port mapping: `docker port mangrullo-web`
2. Verify firewall settings
3. Check container logs: `docker logs mangrullo-web`

## Advanced Usage

### Custom Dockerfile
For custom builds, create a `.dockerignore` file:

```
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
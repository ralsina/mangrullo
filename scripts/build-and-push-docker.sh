#!/bin/bash
set -e

# Login to GHCR
echo "Logging into GitHub Container Registry..."
pass github-registry | docker login ghcr.io -u ralsina --password-stdin

# Configuration
IMAGE_BASE="ghcr.io/ralsina/mangrullo"
VERSION="${1:-latest}"

echo "Building Mangrullo Docker images..."
echo "Version: $VERSION"
echo ""

# Ensure we're using the latest build
echo "Building binaries..."
shards build --without-development --release --static

# Build and push AMD64 image
echo "Building AMD64 image..."
docker buildx build \
  --platform linux/amd64 \
  --tag "${IMAGE_BASE}:${VERSION}" \
  --tag "${IMAGE_BASE}:latest" \
  --push \
  --file Dockerfile \
  .

# Build and push ARM64 image (separate repository)
echo "Building ARM64 image..."
docker buildx build \
  --platform linux/arm64 \
  --tag "${IMAGE_BASE}-arm64:${VERSION}" \
  --tag "${IMAGE_BASE}-arm64:latest" \
  --push \
  --file Dockerfile \
  .

echo ""
echo "✓ Images published successfully:"
echo "  - ${IMAGE_BASE}:latest (AMD64)"
echo "  - ${IMAGE_BASE}-arm64:latest (ARM64)"
echo ""
echo "Usage:"
echo "  AMD64: docker pull ${IMAGE_BASE}:latest"
echo "  ARM64:  docker pull ${IMAGE_BASE}-arm64:latest"

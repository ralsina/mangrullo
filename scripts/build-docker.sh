#!/bin/bash
set -e

# Setup QEMU for multi-architecture builds
docker run --rm --privileged \
  multiarch/qemu-user-static \
  --reset -p yes

# Get version from shard.yml
VERSION=$(shards version)

echo "Building Mangrullo Docker images..."
echo "Version: ${VERSION}"
echo ""

# Login to GHCR
echo "Logging into GitHub Container Registry..."
pass github-registry | docker login ghcr.io -u ralsina --password-stdin

# Build and push AMD64 image
echo "Building Docker image for AMD64..."
docker build . \
  --platform=linux/amd64 \
  --build-arg VERSION="${VERSION}" \
  -t ghcr.io/ralsina/mangrullo:latest \
  -t ghcr.io/ralsina/mangrullo:"${VERSION}" \
  --push

# Build and push ARM64 image
echo "Building Docker image for ARM64..."
docker build . \
  --platform=linux/arm64 \
  --build-arg VERSION="${VERSION}" \
  -t ghcr.io/ralsina/mangrullo-arm64:latest \
  -t ghcr.io/ralsina/mangrullo-arm64:"${VERSION}" \
  --push

echo ""
echo "✓ Images published successfully:"
echo "  AMD64: ghcr.io/ralsina/mangrullo:latest"
echo "  ARM64:  ghcr.io/ralsina/mangrullo-arm64:latest"

#!/bin/bash
set -e

# This script builds the ARM64 Docker image locally on an ARM64 machine
# Run this on your ARM64 server (e.g., Rocky Linux ARM64)

IMAGE_NAME="ghcr.io/ralsina/mangrullo-arm64"
VERSION="${1:-latest}"

echo "Building ARM64 Docker image locally..."
echo "Version: $VERSION"
echo ""

# Login to GHCR
echo "Logging into GHCR..."
pass github-registry | docker login ghcr.io -u ralsina --password-stdin

# Build the image
echo "Building Docker image..."
docker build -t "${IMAGE_NAME}:${VERSION}" -t "${IMAGE_NAME}:latest" .

# Push to GHCR
echo "Pushing to GHCR..."
docker push "${IMAGE_NAME}:${VERSION}"
docker push "${IMAGE_NAME}:latest"

echo ""
echo "✓ ARM64 image built and pushed successfully!"
echo "  ${IMAGE_NAME}:latest"

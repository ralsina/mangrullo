#!/bin/bash
set -e

docker run --rm --privileged \
  multiarch/qemu-user-static \
  --reset -p yes

# Build for AMD64
docker build . -f Dockerfile.static -t mangrullo-builder
docker run --rm -v "$PWD":/app --user="$UID" mangrullo-builder /bin/sh -c "cd /app && rm -rf lib shard.lock && shards build --without-development --release --static"
mv bin/mangrullo bin/mangrullo-static-linux-amd64
mv bin/mangrullo-web bin/mangrullo-web-static-linux-amd64

# Build for ARM64
docker build . -f Dockerfile.static --platform linux/arm64 -t mangrullo-builder
docker run --rm -v "$PWD":/app --platform linux/arm64 --user="$UID" mangrullo-builder /bin/sh -c "cd /app && rm -rf lib shard.lock && shards build --without-development --release --static"
mv bin/mangrullo bin/mangrullo-static-linux-arm64
mv bin/mangrullo-web bin/mangrullo-web-static-linux-arm64
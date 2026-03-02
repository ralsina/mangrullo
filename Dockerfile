# Multi-stage build for optimal image size
FROM alpine:edge AS builder

# Install build dependencies and Crystal
RUN apk add --no-cache \
    build-base \
    crystal \
    shards \
    libxml2-static \
    libxml2-dev \
    libxslt-static \
    libxslt-dev \
    yaml-static \
    yaml-dev \
    openssl-dev \
    openssl-libs-static \
    zlib-dev \
    zlib-static \
    pcre2-dev \
    pcre2-static \
    gc-dev \
    gc-static \
    llvm15-libs \
    musl-dev \
    linux-headers \
    libunwind-dev \
    libunwind-static

WORKDIR /app

# Copy shard files first for better layer caching
COPY shard.yml shard.lock ./

# Install dependencies
RUN shards install --without-development

# Copy source code
COPY . .

# Build both binaries in release mode with static linking
RUN shards build --without-development --release --static

# Final runtime image
FROM alpine:3.20

# Install runtime dependencies
RUN apk add --no-cache \
    ca-certificates \
    docker-cli \
    curl \
    bash

# Create non-root user
RUN addgroup -g 1000 -S mangrullo && \
    adduser -u 1000 -S mangrullo -G mangrullo

WORKDIR /app

# Copy binaries from builder
COPY --from=builder /app/bin/mangrullo /usr/local/bin/
COPY --from=builder /app/bin/mangrullo-web /usr/local/bin/

# Copy entrypoint script
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

# Create directories for data and logs
RUN mkdir -p /var/lib/mangrullo /var/log/mangrullo && \
    chmod +x /usr/local/bin/entrypoint.sh

# Expose port for web interface
EXPOSE 3000

# Set default environment variables
ENV MANGRULLO_SOCKET=/var/run/docker.sock \
    MANGRULLO_LOG_LEVEL=info \
    MANGRULLO_INTERVAL=3600 \
    MANGRULLO_WEB_PORT=3000

# Set entrypoint and default command
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["daemon"]

# Health check for web mode
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:${MANGRULLO_WEB_PORT:-3000}/ || exit 1

# Labels
LABEL org.opencontainers.image.title="Mangrullo" \
      org.opencontainers.image.description="Docker container update manager" \
      org.opencontainers.image.version="0.4.0" \
      org.opencontainers.image.authors="Roberto Alsina <roberto.alsina@gmail.com>" \
      org.opencontainers.image.source="https://github.com/ralsina/mangrullo"

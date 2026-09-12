#!/bin/sh
# Docker healthcheck for Mangrullo containers.
#
# The same image runs either the daemon (which serves its own health
# endpoint on MANGRULLO_HEALTH_PORT) or the web UI (which serves
# GET /health). The entrypoint exec's the binary, so PID 1's command
# line tells us which mode this container is in.
set -e

pid1_command=$(tr '\0' ' ' < /proc/1/cmdline 2>/dev/null || true)

case "$pid1_command" in
    *mangrullo-web*)
        curl -fsS "http://127.0.0.1:${MANGRULLO_WEB_PORT:-3000}/health" > /dev/null
        ;;
    *)
        # Daemon mode (or unknown command): prefer the daemon health endpoint.
        if curl -fsS "http://127.0.0.1:${MANGRULLO_HEALTH_PORT:-3001}/health" > /dev/null 2>&1; then
            exit 0
        fi
        # Fallback for one-shot runs (check/dry-run) with no health endpoint:
        # the container is healthy while its main process is alive.
        kill -0 1
        ;;
esac

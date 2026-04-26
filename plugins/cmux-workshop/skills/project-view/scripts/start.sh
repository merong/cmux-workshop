#!/usr/bin/env bash
# /project-view entry point (redis-chat-ui edition).
# One-shot launcher: dependency check → ensure dist build → boot node server →
# readiness probe. On success, prints a single sentinel line on stdout:
#     READY: http://localhost:11573
# (or your CMUX_WORKSHOP_SERVER_PORT override).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
source "$SCRIPT_DIR/helpers.sh"

# 1) Dependency probe (aborts on its own if anything is missing)
bash "$SCRIPT_DIR/check-deps.sh"

# Reclaim our port if a foreign process is squatting on it. The server binds
# SERVER_PORT (express, default 11573); override via CMUX_WORKSHOP_SERVER_PORT.
free_port_if_foreign        "$SERVER_PORT" "$SERVER_PID_FILE" "$RUNTIME_DIR" "node"
assert_port_available_or_owned "$SERVER_PORT" "$SERVER_PID_FILE" "$RUNTIME_DIR" "node"

cd "$RUNTIME_DIR"

# 2) Ensure the React bundle exists. server.js refuses to start without dist/.
if [ ! -f "$DIST_DIR/index.html" ]; then
    log "dist/index.html missing — building React bundle (npm run build)..."
    if ! npm run build >&2; then
        fail "vite build failed. Inspect output above and rebuild manually:  ( cd $RUNTIME_DIR && npm run build )"
    fi
fi

# 3) Boot the express + WebSocket server (also serves dist/ statically).
if is_pid_owned_by_cwd "$SERVER_PID_FILE" "$RUNTIME_DIR" "node"; then
    log "redis-chat-ui server already running (PID $(cat "$SERVER_PID_FILE"))."
else
    [ -f "$SERVER_PID_FILE" ] && warn "Ignoring stale or unowned PID file: $SERVER_PID_FILE"
    rm -f "$SERVER_PID_FILE"
    log "Starting redis-chat-ui server on $DASHBOARD_URL (logs: $SERVER_LOG_FILE)..."
    PORT="$SERVER_PORT" \
    CMUX_WORKSHOP_SERVER_PORT="$SERVER_PORT" \
    REDIS_URL="$REDIS_URL" \
    STREAM_KEY="$STREAM_KEY" \
        start_background "$SERVER_PID_FILE" "$SERVER_LOG_FILE" node server.js
fi

# 4) Wait for the dashboard to answer.
log "Waiting for $DASHBOARD_URL to come up (up to 60s)..."
if ! wait_for_url "$DASHBOARD_URL" 60; then
    warn "Dashboard did not become ready in time. Last 50 lines of server log:"
    tail -n 50 "$SERVER_LOG_FILE" >&2 || true
    fail "Dashboard not reachable at $DASHBOARD_URL"
fi

log "Dashboard is up."
echo "READY: $DASHBOARD_URL"

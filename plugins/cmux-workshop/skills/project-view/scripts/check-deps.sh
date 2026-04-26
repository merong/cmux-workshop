#!/usr/bin/env bash
# Pre-flight dependency check for project-view.
# Exits 0 when everything is ready. On failure, prints actionable guidance to
# stderr and exits non-zero so start.sh can abort.

set -euo pipefail

# shellcheck source=helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

missing=0
report() {
    warn "$1"
    missing=$((missing + 1))
}

# 1) cmux CLI + running socket
if ! command -v cmux >/dev/null 2>&1; then
    report "cmux CLI not found in PATH. Install the cmux app from https://cmux.dev (or your internal source)."
else
    socket_path="${CMUX_SOCKET_PATH:-$HOME/Library/Application Support/cmux/cmux.sock}"
    if [ ! -S "$socket_path" ]; then
        report "cmux app does not appear to be running (socket missing at $socket_path). Launch the cmux app first."
    fi
fi

# 2) Redis server
if ! command -v redis-cli >/dev/null 2>&1; then
    report "redis-cli not found. Install Redis: brew install redis && brew services start redis"
elif ! redis-cli ping >/dev/null 2>&1; then
    report "Redis server is not responding. Start it: brew services start redis"
fi

# 3) Node.js >= 18
if ! command -v node >/dev/null 2>&1; then
    report "Node.js not found. Install: brew install node (requires version 18 or newer)"
else
    node_major=$(node -p 'process.versions.node.split(".")[0]')
    if [ "$node_major" -lt 18 ]; then
        report "Node.js $node_major detected; need >= 18. Upgrade with: brew upgrade node"
    fi
fi

# 4) npm dependencies for the web stack
if [ ! -d "$WEB_DIR/server/node_modules" ] \
   || [ ! -d "$WEB_DIR/client/node_modules" ]; then
    report "Web dashboard dependencies missing. Run: (cd '$WEB_DIR' && npm run install:all)"
fi

# 5) Python redis package
if ! python3 -c 'import redis' >/dev/null 2>&1; then
    report "Python redis package missing. Run: pip3 install -r '$RUNTIME_DIR/requirements.txt'"
fi

# 6) curl for readiness probe
if ! command -v curl >/dev/null 2>&1; then
    report "curl not found. Install with: brew install curl"
fi

if [ "$missing" -gt 0 ]; then
    warn "$missing dependency issue(s) above must be resolved before /project-view can run."
    exit 1
fi

log "All dependencies satisfied."

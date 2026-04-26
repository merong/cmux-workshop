#!/usr/bin/env bash
# Pre-flight dependency probe for the redis-chat-ui project-view runtime.
# Exits non-zero with install hints when anything is missing.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
source "$SCRIPT_DIR/helpers.sh"

missing=0

# Redis
if ! command -v redis-cli >/dev/null 2>&1; then
    warn "redis-cli not found."
    cat >&2 <<'HINT'
  → Install Redis (macOS):
        brew install redis
        brew services start redis
HINT
    missing=1
elif ! redis-cli ping 2>/dev/null | grep -q '^PONG$'; then
    warn "Redis server is not responding to PING ($REDIS_URL)."
    cat >&2 <<'HINT'
  → Start Redis (macOS):
        brew services start redis
        # or in foreground:
        redis-server
HINT
    missing=1
fi

# Node.js (>= 18)
if ! command -v node >/dev/null 2>&1; then
    warn "node not found."
    cat >&2 <<'HINT'
  → Install Node.js 18+:
        brew install node
HINT
    missing=1
else
    node_major="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
    if [ "${node_major:-0}" -lt 18 ]; then
        warn "node version too old (need ≥ 18, found $(node --version))."
        missing=1
    fi
fi

# npm
if ! command -v npm >/dev/null 2>&1; then
    warn "npm not found (it ships with Node.js)."
    missing=1
fi

# cmux CLI is OPTIONAL — server.js calls 'cmux rpc' for workspace metadata
# and silently degrades when cmux is absent. We only emit a hint.
if ! command -v cmux >/dev/null 2>&1; then
    warn "cmux CLI not found — workspace metadata enrichment will be skipped."
    cat >&2 <<'HINT'
  → If you want workspace titles/colors in the UI:
        sudo ln -sf "/Applications/cmux.app/Contents/Resources/bin/cmux" /usr/local/bin/cmux
HINT
fi

# curl is needed for the readiness probe.
if ! command -v curl >/dev/null 2>&1; then
    warn "curl not found."
    cat >&2 <<'HINT'
  → Install curl:
        brew install curl
HINT
    missing=1
fi

# Vendored runtime present?
if [ ! -f "$RUNTIME_DIR/server.js" ] || [ ! -f "$RUNTIME_DIR/package.json" ]; then
    warn "redis-chat-ui runtime is missing files under $RUNTIME_DIR"
    missing=1
fi

# Node modules — must be installed by the user (we never auto-install).
if [ ! -d "$RUNTIME_DIR/node_modules" ]; then
    warn "runtime/node_modules is missing."
    cat >&2 <<HINT
  → Install dependencies once:
        ( cd "$RUNTIME_DIR" && npm install )
HINT
    missing=1
fi

if [ "$missing" -ne 0 ]; then
    fail "Dependency check failed. Resolve the warnings above and retry."
fi

log "Dependency check passed."

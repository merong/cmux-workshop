#!/usr/bin/env bash
# /project-view entry point.
# One-shot launcher: dependency check → proxy inject → web dev server →
# polling monitor → readiness probe. On success, prints the sentinel
# "READY: http://localhost:5173" to stdout so the calling agent can open it.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
source "$SCRIPT_DIR/helpers.sh"

# 1) Dependency check (aborts on its own if anything is missing)
bash "$SCRIPT_DIR/check-deps.sh"

# Reclaim our ports if a foreign process is squatting on them. The web stack
# binds WEB_PORT (vite, default 13331) and SERVER_PORT (express, default 11573).
# These defaults are deliberately uncommon to dodge collisions; both can be
# overridden via CMUX_WORKSHOP_WEB_PORT / CMUX_WORKSHOP_SERVER_PORT.
free_port_if_foreign "$WEB_PORT"    "$WEB_PID_FILE" "$WEB_DIR" "npm"
free_port_if_foreign "$SERVER_PORT" "$WEB_PID_FILE" "$WEB_DIR" "npm"

# After potential reclaim, re-validate ownership. If still occupied at this
# point it's an unexpected race; bail loudly rather than silently continue.
assert_port_available_or_owned "$WEB_PORT"    "$WEB_PID_FILE" "$WEB_DIR" "npm"
assert_port_available_or_owned "$SERVER_PORT" "$WEB_PID_FILE" "$WEB_DIR" "npm"

cd "$RUNTIME_DIR"

# 2) Socket proxy
log "Checking cmux socket proxy..."
proxy_is_active() {
    local status
    status="$(./cmux-proxy.sh status 2>/dev/null || true)"
    # cmux-proxy.sh is vendored and its status command is human-oriented:
    # inactive still exits 0. Parsing its own status text plus the upstream
    # socket line is more reliable here than pgrep, which can match unrelated
    # proxy.py processes outside this snapshot.
    printf '%s\n' "$status" | grep -Eq '프록시[[:space:]]*: 실행 중 \(PID:' \
        && printf '%s\n' "$status" | grep -Eq 'cmux-real\.sock[[:space:]]*: 존재'
}

if proxy_is_active; then
    log "Proxy already running — reusing."
else
    log "Injecting cmux socket proxy..."
    ./cmux-proxy.sh inject >&2
    if ! proxy_is_active; then
        ./cmux-proxy.sh status >&2 || true
        fail "cmux socket proxy did not report an active proxied socket after inject."
    fi
fi

# 3) Web dashboard (Express + Vite via 'npm run dev')
if is_pid_owned_by_cwd "$WEB_PID_FILE" "$WEB_DIR" "npm"; then
    log "Web dashboard already running (PID $(cat "$WEB_PID_FILE"))."
else
    [ -f "$WEB_PID_FILE" ] && warn "Ignoring stale or unowned web PID file: $WEB_PID_FILE"
    rm -f "$WEB_PID_FILE"
    log "Starting web dashboard on http://localhost:${WEB_PORT} (logs: $WEB_LOG_FILE)..."
    (
        cd "$WEB_DIR"
        # PORT feeds the vendored express server (server/index.js).
        # CMUX_WORKSHOP_WEB_PORT / _SERVER_PORT feed scripts/dev.js + vite.
        PORT="$SERVER_PORT" \
        CMUX_WORKSHOP_WEB_PORT="$WEB_PORT" \
        CMUX_WORKSHOP_SERVER_PORT="$SERVER_PORT" \
            start_background "$WEB_PID_FILE" "$WEB_LOG_FILE" npm run dev
    )
fi

# 4) Polling monitor (terminal-screen capture)
if is_pid_owned_by_cwd "$POLLING_PID_FILE" "$RUNTIME_DIR" "polling_monitor.py"; then
    log "Polling monitor already running (PID $(cat "$POLLING_PID_FILE"))."
else
    [ -f "$POLLING_PID_FILE" ] && warn "Ignoring stale or unowned polling PID file: $POLLING_PID_FILE"
    rm -f "$POLLING_PID_FILE"
    log "Starting polling monitor (logs: $POLLING_LOG_FILE)..."
    start_background "$POLLING_PID_FILE" "$POLLING_LOG_FILE" python3 "$RUNTIME_DIR/polling_monitor.py"
fi

# 5) Wait for the dashboard to answer
log "Waiting for $DASHBOARD_URL to come up (up to 60s)..."
if ! wait_for_url "$DASHBOARD_URL" 60; then
    warn "Dashboard did not become ready in time. Last 50 lines of web log:"
    tail -n 50 "$WEB_LOG_FILE" >&2 || true
    fail "Dashboard not reachable at $DASHBOARD_URL"
fi

log "Dashboard is up."
echo "READY: $DASHBOARD_URL"

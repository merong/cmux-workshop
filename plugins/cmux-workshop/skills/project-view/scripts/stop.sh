#!/usr/bin/env bash
# /project-view-stop entry point (redis-chat-ui edition).
# Idempotently stops the launcher-owned node server and cleans the log file.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
source "$SCRIPT_DIR/helpers.sh"

stop_owned_pid() {
    # stop_owned_pid <label> <pid_file> <expected_cwd> [command_substring]
    local label="$1" pid_file="$2" expected_cwd="$3" expected_cmd="${4:-}" pid

    if ! pid="$(read_pid_file "$pid_file" 2>/dev/null)"; then
        log "$label is not running (no valid PID file)."
        rm -f "$pid_file"
        return 0
    fi

    if is_pid_owned_by_cwd "$pid_file" "$expected_cwd" "$expected_cmd"; then
        log "Stopping $label (PID $pid)..."
        kill "$pid" 2>/dev/null || true
        sleep 1
        if kill -0 "$pid" 2>/dev/null; then
            warn "$label did not exit after SIGTERM; sending SIGKILL."
            kill -9 "$pid" 2>/dev/null || true
        fi
    elif kill -0 "$pid" 2>/dev/null; then
        warn "Skipping $label kill: PID $pid is not owned by this project-view runtime."
    else
        log "$label PID file was stale (PID $pid is not alive)."
    fi

    rm -f "$pid_file"
}

stop_owned_pid "redis-chat-ui server" "$SERVER_PID_FILE" "$RUNTIME_DIR" "node"

# Clean the log so the next start writes from scratch (mirrors prior behavior).
rm -f "$SERVER_LOG_FILE"

echo "STOPPED: project-view"

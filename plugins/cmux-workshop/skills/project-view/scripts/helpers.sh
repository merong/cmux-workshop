#!/usr/bin/env bash
# Shared helpers for project-view scripts. PID/log files and log prefix
# keep the cmux-workshop plugin identifier on purpose.
# Source this file; do not execute it directly.

set -euo pipefail

SKILL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_DIR="$SKILL_ROOT/runtime"
WEB_DIR="$RUNTIME_DIR/web"

WEB_PID_FILE="/tmp/cmux-workshop-web.pid"
WEB_LOG_FILE="/tmp/cmux-workshop-web.log"
POLLING_PID_FILE="/tmp/cmux-workshop-polling.pid"
POLLING_LOG_FILE="/tmp/cmux-workshop-polling.log"

# Defaults are deliberately uncommon ports to dodge collisions with other
# Vite/Express dev stacks (5173/3001 are too popular). Override with
# CMUX_WORKSHOP_WEB_PORT / CMUX_WORKSHOP_SERVER_PORT.
WEB_PORT="${CMUX_WORKSHOP_WEB_PORT:-13331}"
SERVER_PORT="${CMUX_WORKSHOP_SERVER_PORT:-11573}"
export CMUX_WORKSHOP_WEB_PORT="$WEB_PORT"
export CMUX_WORKSHOP_SERVER_PORT="$SERVER_PORT"

DASHBOARD_URL="http://localhost:${WEB_PORT}"
SERVER_URL="http://localhost:${SERVER_PORT}"

log()  { printf '[cmux-workshop] %s\n' "$*" >&2; }
warn() { printf '[cmux-workshop][warn] %s\n' "$*" >&2; }
fail() { printf '[cmux-workshop][error] %s\n' "$*" >&2; exit 1; }

is_pid_alive() {
    local pid_file="$1"
    [ -f "$pid_file" ] || return 1
    local pid
    pid="$(cat "$pid_file" 2>/dev/null || true)"
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

read_pid_file() {
    local pid_file="$1" pid
    [ -f "$pid_file" ] || return 1
    pid="$(cat "$pid_file" 2>/dev/null || true)"
    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    echo "$pid"
}

pid_command() {
    local pid="$1"
    ps -p "$pid" -o command= 2>/dev/null | sed 's/^[[:space:]]*//' || true
}

pid_cwd() {
    local pid="$1"
    lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -n 1 || true
}

same_dir() {
    local a="$1" b="$2"
    [ -n "$a" ] && [ -n "$b" ] || return 1
    [ -d "$a" ] && [ -d "$b" ] || return 1
    [ "$(cd "$a" && pwd -P)" = "$(cd "$b" && pwd -P)" ]
}

is_pid_owned_by_cwd() {
    # is_pid_owned_by_cwd <pid_file> <expected_cwd> [command_substring]
    # Guards against /tmp PID reuse before start.sh reuses or stop.sh kills.
    local pid_file="$1" expected_cwd="$2" expected_cmd="${3:-}" pid cwd command
    pid="$(read_pid_file "$pid_file")" || return 1
    kill -0 "$pid" 2>/dev/null || return 1

    cwd="$(pid_cwd "$pid")"
    same_dir "$cwd" "$expected_cwd" || return 1

    if [ -n "$expected_cmd" ]; then
        command="$(pid_command "$pid")"
        [[ "$command" == *"$expected_cmd"* ]] || return 1
    fi
}

pid_is_descendant_of() {
    local child="$1" ancestor="$2" parent
    while [[ "$child" =~ ^[0-9]+$ ]] && [ "$child" -gt 1 ]; do
        [ "$child" = "$ancestor" ] && return 0
        parent="$(ps -p "$child" -o ppid= 2>/dev/null | tr -d '[:space:]')"
        [ -n "$parent" ] || break
        child="$parent"
    done
    return 1
}

port_listener_pids() {
    local port="$1"
    lsof -nP -iTCP:"$port" -sTCP:LISTEN -t 2>/dev/null | sort -u || true
}

assert_port_available_or_owned() {
    # assert_port_available_or_owned <port> <pid_file> <expected_cwd> [command_substring]
    local port="$1" pid_file="$2" expected_cwd="$3" expected_cmd="${4:-}" owner_pid listener_pids listener
    listener_pids="$(port_listener_pids "$port")"
    [ -n "$listener_pids" ] || return 0

    if is_pid_owned_by_cwd "$pid_file" "$expected_cwd" "$expected_cmd"; then
        owner_pid="$(read_pid_file "$pid_file")"
        while IFS= read -r listener; do
            [ -n "$listener" ] || continue
            if ! pid_is_descendant_of "$listener" "$owner_pid"; then
                warn "Port $port is held by PID $listener, not by the owned process tree rooted at PID $owner_pid."
                lsof -nP -iTCP:"$port" -sTCP:LISTEN >&2 || true
                fail "Port $port is already in use by another process."
            fi
        done <<< "$listener_pids"
        return 0
    fi

    lsof -nP -iTCP:"$port" -sTCP:LISTEN >&2 || true
    fail "Port $port is already in use and is not owned by $pid_file for this project-view runtime."
}

kill_port_holders() {
    # kill_port_holders <port> [reason]
    # Forcefully terminates every process holding TCP <port> in LISTEN.
    # SIGTERM first, then SIGKILL after a short grace period.
    local port="$1" reason="${2:-}" listener_pids listener
    listener_pids="$(port_listener_pids "$port")"
    [ -n "$listener_pids" ] || return 0

    if [ -n "$reason" ]; then
        warn "Reclaiming port $port ($reason). Listeners:"
    else
        warn "Reclaiming port $port. Listeners:"
    fi
    lsof -nP -iTCP:"$port" -sTCP:LISTEN >&2 || true

    while IFS= read -r listener; do
        [ -n "$listener" ] || continue
        kill "$listener" 2>/dev/null || true
    done <<< "$listener_pids"

    # Brief settle window before escalating to SIGKILL.
    local waited=0
    while [ "$waited" -lt 3 ]; do
        listener_pids="$(port_listener_pids "$port")"
        [ -z "$listener_pids" ] && return 0
        sleep 1
        waited=$((waited + 1))
    done

    while IFS= read -r listener; do
        [ -n "$listener" ] || continue
        warn "Force killing PID $listener still bound to port $port."
        kill -9 "$listener" 2>/dev/null || true
    done <<< "$listener_pids"

    sleep 1
    listener_pids="$(port_listener_pids "$port")"
    if [ -n "$listener_pids" ]; then
        lsof -nP -iTCP:"$port" -sTCP:LISTEN >&2 || true
        fail "Port $port still occupied after SIGKILL: $listener_pids"
    fi
}

free_port_if_foreign() {
    # free_port_if_foreign <port> <pid_file> <expected_cwd> [command_substring]
    # If the port is held by something other than our tracked PID tree, kill it.
    local port="$1" pid_file="$2" expected_cwd="$3" expected_cmd="${4:-}"
    local listener_pids owner_pid listener foreign

    listener_pids="$(port_listener_pids "$port")"
    [ -n "$listener_pids" ] || return 0

    if is_pid_owned_by_cwd "$pid_file" "$expected_cwd" "$expected_cmd"; then
        owner_pid="$(read_pid_file "$pid_file")"
        foreign=""
        while IFS= read -r listener; do
            [ -n "$listener" ] || continue
            pid_is_descendant_of "$listener" "$owner_pid" \
                || foreign="${foreign}${listener} "
        done <<< "$listener_pids"
        [ -z "$foreign" ] && return 0
        kill_port_holders "$port" "foreign listener(s) outside owned tree"
        return 0
    fi

    kill_port_holders "$port" "no project-view ownership recorded"
}

start_background() {
    # start_background <pid_file> <log_file> <command...>
    local pid_file="$1" log_file="$2"
    shift 2
    : > "$log_file"
    nohup "$@" >>"$log_file" 2>&1 &
    echo $! > "$pid_file"
}

wait_for_url() {
    # wait_for_url <url> <timeout_seconds>
    local url="$1" timeout="${2:-30}" elapsed=0
    while [ "$elapsed" -lt "$timeout" ]; do
        if curl -fsS -o /dev/null --max-time 2 "$url"; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    return 1
}

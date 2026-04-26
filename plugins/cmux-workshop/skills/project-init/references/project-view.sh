#!/usr/bin/env bash
# project-view wrapper — resolves to the installed cmux-workshop start.sh.
#
# Copied to .claude/script/project-view.sh by `project-init` so the project
# can launch the cmux monitor stack directly from a plain shell, without
# routing through Claude Code's slash command surface.
#
# Usage:
#   .claude/script/project-view.sh [start|stop|check]
#
# Subcommands:
#   start  (default) launch proxy + web + polling, print "READY: <url>"
#   stop   shut down web + polling + proxy idempotently
#   check  run dependency probe only
#
# Environment overrides (first match wins):
#   CMUX_WORKSHOP_HOME       absolute path to a local cmux-workshop clone
#   CLAUDE_PLUGIN_ROOT       set automatically inside a Claude Code session
#   ~/.claude/plugins/cache  marketplace cache, latest version auto-picked
#
# Port overrides (forwarded into start.sh):
#   CMUX_WORKSHOP_WEB_PORT     vite dev port  (default 13331)
#   CMUX_WORKSHOP_SERVER_PORT  express port   (default 11573)
#
# start.sh forcibly reclaims either port if a foreign process is squatting on
# it (SIGTERM, then SIGKILL). Use the env vars above to pick different ports
# instead of killing the squatter.

set -euo pipefail

resolve_scripts_dir() {
  local candidate

  if [ -n "${CMUX_WORKSHOP_HOME:-}" ]; then
    candidate="$CMUX_WORKSHOP_HOME/plugins/cmux-workshop/skills/project-view/scripts"
    if [ -x "$candidate/start.sh" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi

  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    candidate="$CLAUDE_PLUGIN_ROOT/skills/project-view/scripts"
    if [ -x "$candidate/start.sh" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi

  local mp_base="$HOME/.claude/plugins/cache/cmux-workshop/cmux-workshop"
  if [ -d "$mp_base" ]; then
    local ver
    ver=$(ls -1 "$mp_base" 2>/dev/null | sort -V | tail -1 || true)
    if [ -n "$ver" ]; then
      candidate="$mp_base/$ver/skills/project-view/scripts"
      if [ -x "$candidate/start.sh" ]; then
        printf '%s\n' "$candidate"
        return 0
      fi
    fi
  fi

  return 1
}

if ! PV_SCRIPTS=$(resolve_scripts_dir); then
  cat >&2 <<'HINT'
[project-view.sh] cmux-workshop 플러그인을 찾을 수 없습니다.
다음 중 하나로 해결하세요:
  • Claude Code 안에서:  /plugin install cmux-workshop@cmux-workshop
  • 로컬 클론을 사용:   CMUX_WORKSHOP_HOME=/path/to/cmux-workshop "$0" "$@"
HINT
  exit 2
fi

sub="${1:-start}"
shift || true

case "$sub" in
  start)
    exec bash "$PV_SCRIPTS/start.sh" "$@"
    ;;
  stop)
    exec bash "$PV_SCRIPTS/stop.sh" "$@"
    ;;
  check|check-deps)
    exec bash "$PV_SCRIPTS/check-deps.sh" "$@"
    ;;
  --help|-h|help)
    cat <<USAGE
Usage: $0 [start|stop|check]
  start  (default) launch proxy + web + polling, then print READY URL
  stop   shut down web + polling + proxy
  check  run dependency probe only

Default ports (override with env vars):
  CMUX_WORKSHOP_WEB_PORT     vite dev port  (default 13331)
  CMUX_WORKSHOP_SERVER_PORT  express port   (default 11573)

Resolved scripts dir: $PV_SCRIPTS
USAGE
    ;;
  *)
    echo "Unknown subcommand: $sub" >&2
    echo "Usage: $0 [start|stop|check]" >&2
    exit 64
    ;;
esac

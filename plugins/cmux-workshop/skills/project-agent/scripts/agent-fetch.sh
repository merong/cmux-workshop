#!/usr/bin/env bash
# agent-fetch.sh — Copy/download a single agent persona .md to a destination.
#
# Usage:
#   agent-fetch.sh --source local --name NAME --dest PATH
#   agent-fetch.sh --source voltagent --category CAT --name NAME --dest PATH
#
# Sources:
#   local       Copies from ${CLAUDE_PLUGIN_ROOT}/agents/<NAME>.md
#   voltagent   Downloads from VoltAgent/awesome-claude-code-subagents via gh CLI
#
# Output:
#   On success: prints "OK <source> <resolved-origin> -> <dest>"
#   On failure: exits non-zero with error on stderr
#
# Environment:
#   CLAUDE_PLUGIN_ROOT  Path to the plugin root (fallback: infer from script dir)

set -euo pipefail

SOURCE=""
NAME=""
CATEGORY=""
DEST=""

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)   SOURCE="$2"; shift 2 ;;
    --name)     NAME="$2"; shift 2 ;;
    --category) CATEGORY="$2"; shift 2 ;;
    --dest)     DEST="$2"; shift 2 ;;
    --help|-h)  usage ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$SOURCE" ]] || { echo "--source required (local|voltagent)" >&2; exit 2; }
[[ -n "$NAME"   ]] || { echo "--name required" >&2; exit 2; }
[[ -n "$DEST"   ]] || { echo "--dest required" >&2; exit 2; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"

mkdir -p "$(dirname "$DEST")"

case "$SOURCE" in
  local)
    src="${PLUGIN_ROOT}/agents/${NAME}.md"
    if [[ ! -f "$src" ]]; then
      echo "Local agent not found: $src" >&2
      exit 1
    fi
    cp "$src" "$DEST"
    echo "OK local ${src#${PLUGIN_ROOT}/} -> $DEST"
    ;;

  voltagent)
    command -v gh >/dev/null 2>&1 || {
      echo "gh CLI not found; required for voltagent source" >&2
      exit 1
    }
    [[ -n "$CATEGORY" ]] || { echo "--category required for voltagent source" >&2; exit 2; }

    remote_path="categories/${CATEGORY}/${NAME}.md"
    tmp="$(mktemp)"
    trap 'rm -f "$tmp"' EXIT

    if ! gh api "repos/VoltAgent/awesome-claude-code-subagents/contents/${remote_path}" \
          --jq '.content' 2>/tmp/agent-fetch.err | base64 -d > "$tmp"; then
      echo "gh api failed for $remote_path" >&2
      [[ -s /tmp/agent-fetch.err ]] && cat /tmp/agent-fetch.err >&2
      exit 1
    fi

    if [[ ! -s "$tmp" ]]; then
      echo "Fetched empty content from $remote_path" >&2
      exit 1
    fi

    mv "$tmp" "$DEST"
    trap - EXIT
    echo "OK voltagent ${remote_path} -> $DEST"
    ;;

  *)
    echo "--source must be local or voltagent" >&2
    exit 2
    ;;
esac

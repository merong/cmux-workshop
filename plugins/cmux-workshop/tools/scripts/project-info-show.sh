#!/usr/bin/env bash
# project-info-show.sh — Show the project_info row.
#
# Usage:
#   project-info-show.sh [--db PATH] [--json]
#
# Default output: aligned key/value block.
# With --json: raw JSON object (empty object if no capture yet).
#
# Exit codes:
#   0 — success (even if no row exists)
#   1 — DB missing

set -euo pipefail

DB_PATH=""
JSON=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --db)   DB_PATH="$2"; shift 2 ;;
    --json) JSON=1; shift ;;
    --help|-h) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DB_SH="$TOOLS_DIR/db.sh"
QUERY="$TOOLS_DIR/queries/get-project-info.sql"

[[ -z "$DB_PATH" ]] && DB_PATH="$PWD/.claude/project.db"
export CMUX_WORKSHOP_DB_PATH="$DB_PATH"

if ! "$DB_SH" exists; then
  echo "project.db not found at $DB_PATH" >&2
  exit 1
fi

JSON_OUT=$("$DB_SH" json "$(cat "$QUERY")")

if [[ $JSON -eq 1 ]]; then
  echo "$JSON_OUT"
  exit 0
fi

python3 - "$JSON_OUT" <<'PY'
import json, sys
rows = json.loads(sys.argv[1] or '[]')
if not rows:
    print("No project_info captured yet. Run: tools/scripts/project-info-capture.sh")
    sys.exit(0)
r = rows[0]
label = lambda k: k.replace('_', ' ').title()
order = [
    'project_name', 'project_summary', 'project_root',
    'cmux_workspace_id', 'cmux_workspace_title', 'cmux_socket_path',
    'git_remote_url', 'git_branch',
    'captured_at', 'created_at', 'updated_at',
]
width = max(len(label(k)) for k in order)
print("Project Info")
print("─" * 40)
for k in order:
    v = r.get(k) or '—'
    print(f"  {label(k):<{width}} : {v}")
PY

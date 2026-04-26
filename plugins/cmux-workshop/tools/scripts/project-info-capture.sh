#!/usr/bin/env bash
# project-info-capture.sh — Snapshot the current project + cmux workspace
#                           environment into project_info (singleton row).
#
# Usage:
#   project-info-capture.sh [--name NAME] [--summary TEXT]
#                           [--root PATH]
#                           [--db PATH]
#                           [--quiet]
#
# Behavior:
#   - Resolves project_root from --root, else $PWD (absolute).
#   - Derives project_name from --name, else basename of project_root.
#   - Reads CMUX_WORKSPACE_ID / CMUX_SOCKET_PATH from env.
#   - Queries cmux for current workspace title (best-effort).
#   - Reads git remote.origin.url + current branch (best-effort).
#   - Initializes .claude/project.db if missing.
#   - Upserts project_info row.
#
# Exit codes:
#   0 — success
#   2 — bad arguments
#   3 — db.sh missing / sqlite3 missing

set -euo pipefail

PROJECT_NAME=""
PROJECT_SUMMARY=""
PROJECT_ROOT=""
DB_PATH=""
QUIET=0

usage() { sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)    PROJECT_NAME="$2"; shift 2 ;;
    --summary) PROJECT_SUMMARY="$2"; shift 2 ;;
    --root)    PROJECT_ROOT="$2"; shift 2 ;;
    --db)      DB_PATH="$2"; shift 2 ;;
    --quiet)   QUIET=1; shift ;;
    --help|-h) usage ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DB_SH="$TOOLS_DIR/db.sh"

[[ -x "$DB_SH" ]] || { echo "db.sh not found/executable at $DB_SH" >&2; exit 3; }

# ── Resolve project_root ────────────────────────────────────────
if [[ -z "$PROJECT_ROOT" ]]; then
  PROJECT_ROOT="$PWD"
fi
# Make absolute + canonical
PROJECT_ROOT="$(cd "$PROJECT_ROOT" 2>/dev/null && pwd -P)" || {
  echo "Cannot resolve project_root: $PROJECT_ROOT" >&2
  exit 2
}

# ── project_name default ────────────────────────────────────────
[[ -z "$PROJECT_NAME" ]] && PROJECT_NAME="$(basename "$PROJECT_ROOT")"

# ── DB path default (relative to project_root) ──────────────────
[[ -z "$DB_PATH" ]] && DB_PATH="$PROJECT_ROOT/.claude/project.db"

export CMUX_WORKSHOP_DB_PATH="$DB_PATH"

# ── Initialize schema if needed ─────────────────────────────────
"$DB_SH" init

# ── Gather cmux info (best-effort) ──────────────────────────────
CMUX_WORKSPACE_ID_VAL="${CMUX_WORKSPACE_ID:-}"
CMUX_SOCKET_PATH_VAL="${CMUX_SOCKET_PATH:-}"
CMUX_WORKSPACE_TITLE_VAL=""

if [[ -n "$CMUX_WORKSPACE_ID_VAL" ]] && command -v cmux >/dev/null 2>&1; then
  # Find title of the selected workspace in the current window
  CMUX_WORKSPACE_TITLE_VAL=$(
    cmux tree --json 2>/dev/null \
      | python3 -c '
import json, sys
try:
    tree = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for w in tree.get("windows", []):
    for ws in w.get("workspaces", []):
        if ws.get("selected"):
            print(ws.get("title", ""))
            sys.exit(0)
' || true
  )
fi

# ── Gather git info (best-effort) ───────────────────────────────
GIT_REMOTE_URL_VAL=""
GIT_BRANCH_VAL=""
if command -v git >/dev/null 2>&1 && git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  GIT_REMOTE_URL_VAL="$(git -C "$PROJECT_ROOT" config --get remote.origin.url 2>/dev/null || true)"
  GIT_BRANCH_VAL="$(git -C "$PROJECT_ROOT" symbolic-ref --short HEAD 2>/dev/null || true)"
fi

# ── SQL-quote helper ────────────────────────────────────────────
sql_lit() {
  # Emits SQL literal: 'value' if non-empty, else bare NULL
  if [[ -z "${1-}" ]]; then
    printf 'NULL'
  else
    "$DB_SH" quote "$1"
  fi
}

NAME_SQL=$("$DB_SH" quote "$PROJECT_NAME")
SUMMARY_SQL=$(sql_lit "$PROJECT_SUMMARY")
ROOT_SQL=$("$DB_SH" quote "$PROJECT_ROOT")
WSID_SQL=$(sql_lit "$CMUX_WORKSPACE_ID_VAL")
WSTITLE_SQL=$(sql_lit "$CMUX_WORKSPACE_TITLE_VAL")
SOCK_SQL=$(sql_lit "$CMUX_SOCKET_PATH_VAL")
GITREMOTE_SQL=$(sql_lit "$GIT_REMOTE_URL_VAL")
GITBRANCH_SQL=$(sql_lit "$GIT_BRANCH_VAL")

TEMPLATE="$TOOLS_DIR/queries/upsert-project-info.sql"

# Render template into a tempfile, then run through db.sh
TMP_SQL=$(mktemp)
trap 'rm -f "$TMP_SQL"' EXIT

sed \
  -e "s|{PROJECT_NAME}|${NAME_SQL//|/\\|}|g" \
  -e "s|{PROJECT_SUMMARY}|${SUMMARY_SQL//|/\\|}|g" \
  -e "s|{PROJECT_ROOT}|${ROOT_SQL//|/\\|}|g" \
  -e "s|{CMUX_WORKSPACE_ID}|${WSID_SQL//|/\\|}|g" \
  -e "s|{CMUX_WORKSPACE_TITLE}|${WSTITLE_SQL//|/\\|}|g" \
  -e "s|{CMUX_SOCKET_PATH}|${SOCK_SQL//|/\\|}|g" \
  -e "s|{GIT_REMOTE_URL}|${GITREMOTE_SQL//|/\\|}|g" \
  -e "s|{GIT_BRANCH}|${GITBRANCH_SQL//|/\\|}|g" \
  "$TEMPLATE" > "$TMP_SQL"

"$DB_SH" run "$TMP_SQL"

if [[ $QUIET -ne 1 ]]; then
  printf 'OK captured project_info:\n'
  printf '  project_name         : %s\n' "$PROJECT_NAME"
  printf '  project_root         : %s\n' "$PROJECT_ROOT"
  printf '  cmux_workspace_id    : %s\n' "${CMUX_WORKSPACE_ID_VAL:-<none>}"
  printf '  cmux_workspace_title : %s\n' "${CMUX_WORKSPACE_TITLE_VAL:-<none>}"
  printf '  git_remote_url       : %s\n' "${GIT_REMOTE_URL_VAL:-<none>}"
  printf '  git_branch           : %s\n' "${GIT_BRANCH_VAL:-<none>}"
  printf '  db                   : %s\n' "$DB_PATH"
fi

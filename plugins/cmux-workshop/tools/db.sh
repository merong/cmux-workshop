#!/usr/bin/env bash
# db.sh — SQLite wrapper for cmux-workshop's .claude/project.db
#
# Usage:
#   db.sh init                    Create schema (idempotent)
#   db.sh migrate                 Create schema and apply tools/migrations/*.sql
#   db.sh exists                  Exit 0 if project.db exists, 1 otherwise
#   db.sh path                    Print resolved db path
#   db.sh exec "<SQL>"            Execute SQL (writes OK, no output on success)
#   db.sh query "<SQL>"           Execute SQL, pipe-delimited output with header
#   db.sh json "<SQL>"            Execute SQL, JSON array output
#   db.sh scalar "<SQL>"          Execute SQL, single value (first row/col, raw)
#   db.sh run <file.sql>          Execute SQL file (literal, no substitution)
#   db.sh quote <value>           Print SQL-escaped literal (wrapped in single quotes)
#
# Environment:
#   CMUX_WORKSHOP_DB_PATH    Override db path (default: $PWD/.claude/project.db)
#   CMUX_WORKSHOP_DEBUG=1    Print sqlite3 invocations to stderr

set -euo pipefail

DB_PATH="${CMUX_WORKSHOP_DB_PATH:-${PWD}/.claude/project.db}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCHEMA_FILE="${SCRIPT_DIR}/schema.sql"
MIGRATIONS_DIR="${SCRIPT_DIR}/migrations"

log() { [[ "${CMUX_WORKSHOP_DEBUG:-0}" == "1" ]] && echo "db.sh: $*" >&2 || true; }

have_sqlite() {
  command -v sqlite3 >/dev/null 2>&1 || {
    echo "sqlite3 not found; install via 'brew install sqlite' or 'apt install sqlite3'" >&2
    exit 127
  }
}

ensure_parent() {
  local dir
  dir="$(dirname "$DB_PATH")"
  [[ -d "$dir" ]] || mkdir -p "$dir"
}

cmd_init() {
  have_sqlite
  ensure_parent
  [[ -f "$SCHEMA_FILE" ]] || { echo "schema.sql missing at $SCHEMA_FILE" >&2; exit 2; }
  log "init: $DB_PATH"
  sqlite3 "$DB_PATH" < "$SCHEMA_FILE"
}

cmd_migrate() {
  have_sqlite
  ensure_parent
  cmd_init
  [[ -d "$MIGRATIONS_DIR" ]] || { log "migrate: no migrations dir at $MIGRATIONS_DIR"; return 0; }

  local current legacy version file base
  current="$(cmd_scalar "SELECT value FROM metadata WHERE key = 'schema_version'" 2>/dev/null || true)"
  if [[ -z "$current" ]]; then
    legacy="$(cmd_scalar "SELECT schema_version FROM project WHERE id = 1" 2>/dev/null || true)"
    if [[ "$legacy" =~ ^[0-9]+$ ]]; then
      current="$legacy"
    else
      current="1"
    fi
    cmd_exec "INSERT OR REPLACE INTO metadata (key, value) VALUES ('schema_version', '$current')"
  fi

  for file in "$MIGRATIONS_DIR"/*.sql; do
    [[ -e "$file" ]] || continue
    base="$(basename "$file")"
    version="$(printf '%s\n' "$base" | sed -E 's/^0*([0-9]+)_.*/\1/')"
    [[ "$version" =~ ^[0-9]+$ ]] || continue
    if (( version <= current )); then
      log "migrate: skip $base (current=$current)"
      continue
    fi
    log "migrate: apply $base"
    cmd_run "$file"
    cmd_exec "INSERT OR REPLACE INTO metadata (key, value) VALUES ('schema_version', '$version')"
    cmd_exec "UPDATE project SET schema_version = $version WHERE id = 1"
    current="$version"
  done
}

cmd_exists() {
  [[ -f "$DB_PATH" ]]
}

cmd_path() {
  echo "$DB_PATH"
}

cmd_exec() {
  have_sqlite
  local sql="${1:?exec requires SQL string}"
  log "exec: $sql"
  sqlite3 "$DB_PATH" "PRAGMA foreign_keys=ON; $sql"
}

cmd_query() {
  have_sqlite
  local sql="${1:?query requires SQL string}"
  log "query: $sql"
  # -header -separator '|' to give predictable parseable output
  sqlite3 -header -separator '|' "$DB_PATH" "PRAGMA foreign_keys=ON; $sql"
}

cmd_json() {
  have_sqlite
  local sql="${1:?json requires SQL string}"
  log "json: $sql"
  # sqlite3 .mode json (available since 3.33.0) emits JSON array of objects
sqlite3 "$DB_PATH" <<EOF
PRAGMA foreign_keys=ON;
.mode json
$sql
EOF
}

cmd_scalar() {
  have_sqlite
  local sql="${1:?scalar requires SQL string}"
  log "scalar: $sql"
  sqlite3 "$DB_PATH" "PRAGMA foreign_keys=ON; $sql"
}

cmd_run() {
  have_sqlite
  local file="${1:?run requires SQL file path}"
  [[ -f "$file" ]] || { echo "SQL file not found: $file" >&2; exit 2; }
  log "run: $file"
  {
    printf 'PRAGMA foreign_keys=ON;\n'
    cat "$file"
  } | sqlite3 "$DB_PATH"
}

cmd_quote() {
  local val="${1-}"
  # Escape single quotes by doubling them (SQLite literal rule)
  printf "'%s'" "${val//\'/\'\'}"
}

cmd="${1:-}"
[[ -n "$cmd" ]] || { sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }
shift

case "$cmd" in
  init)    cmd_init "$@" ;;
  migrate) cmd_migrate "$@" ;;
  exists)  cmd_exists "$@" ;;
  path)    cmd_path "$@" ;;
  exec)    cmd_exec "$@" ;;
  query)   cmd_query "$@" ;;
  json)    cmd_json "$@" ;;
  scalar)  cmd_scalar "$@" ;;
  run)     cmd_run "$@" ;;
  quote)   cmd_quote "$@" ;;
  --help|-h) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) echo "Unknown subcommand: $cmd" >&2; exit 2 ;;
esac

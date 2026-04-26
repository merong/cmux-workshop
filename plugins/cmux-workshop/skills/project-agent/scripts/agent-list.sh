#!/usr/bin/env bash
# agent-list.sh — List available agent personas from local library and VoltAgent.
#
# Usage:
#   agent-list.sh [--source local|voltagent|all]
#                 [--category CATEGORY]
#                 [--keyword KEYWORD]
#                 [--json]
#
# Output:
#   - Plain text: one agent per line with source, name, description
#   - JSON (--json): {"agents": [{source, name, description, path/category, model?}, ...]}
#
# Sources:
#   local       Plugin-bundled personas at ${CLAUDE_PLUGIN_ROOT}/agents/
#   voltagent   VoltAgent/awesome-claude-code-subagents GitHub repo (via gh CLI)
#   all         Both (local listed first)
#
# Environment:
#   CLAUDE_PLUGIN_ROOT  Path to the plugin root (fallback: infer from script dir)

set -euo pipefail

SOURCE="all"
CATEGORY=""
KEYWORD=""
JSON=0

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)   SOURCE="$2"; shift 2 ;;
    --category) CATEGORY="$2"; shift 2 ;;
    --keyword)  KEYWORD="$2"; shift 2 ;;
    --json)     JSON=1; shift ;;
    --help|-h)  usage ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

case "$SOURCE" in
  local|voltagent|all) ;;
  *) echo "--source must be local|voltagent|all" >&2; exit 2 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# project-agent/scripts -> plugin root is ../../..
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"
AGENTS_DIR="${PLUGIN_ROOT}/agents"

VOLTAGENT_REPO="VoltAgent/awesome-claude-code-subagents"
VOLTAGENT_CATEGORIES=(
  "01-core-development"
  "02-language-specialists"
  "03-infrastructure"
  "04-quality-security"
  "05-data-ai"
  "06-developer-experience"
  "07-specialized-domains"
  "08-business-product"
  "09-meta-orchestration"
  "10-research-analysis"
)

# Parse a frontmatter field (name/description/model) from a markdown file.
# Handles quoted and unquoted values; returns empty if missing.
parse_fm_field() {
  local file="$1" field="$2"
  awk -v f="$field" '
    BEGIN { in_fm=0 }
    /^---[[:space:]]*$/ { in_fm = !in_fm; next }
    in_fm && $0 ~ "^" f ":" {
      sub("^" f ":[[:space:]]*", "")
      gsub(/^"|"$/, "")
      gsub(/^'\''|'\''$/, "")
      print
      exit
    }
  ' "$file" 2>/dev/null || true
}

# Escape a string for safe JSON encoding (basic: backslash, quote, control).
json_escape() {
  python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1" 2>/dev/null \
    || printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')"
}

matches_keyword() {
  local hay="$1"
  [[ -z "$KEYWORD" ]] && return 0
  [[ "$(printf '%s' "$hay" | tr '[:upper:]' '[:lower:]')" == *"$(printf '%s' "$KEYWORD" | tr '[:upper:]' '[:lower:]')"* ]]
}

US=$'\x1f'  # ASCII Unit Separator — used between record fields (non-whitespace, safe with IFS)

collect_local() {
  [[ -d "$AGENTS_DIR" ]] || return 0
  local f name desc model
  while IFS= read -r -d '' f; do
    name=$(parse_fm_field "$f" "name")
    [[ -z "$name" ]] && name="$(basename "$f" .md)"
    desc=$(parse_fm_field "$f" "description")
    model=$(parse_fm_field "$f" "model")
    if matches_keyword "${name} ${desc}"; then
      printf 'local%s%s%s%s%s%s%s%s\n' "$US" "$name" "$US" "$desc" "$US" "$f" "$US" "$model"
    fi
  done < <(find "$AGENTS_DIR" -maxdepth 1 -type f -name '*.md' -print0 2>/dev/null)
}

collect_voltagent() {
  command -v gh >/dev/null 2>&1 || {
    echo "gh CLI not found; cannot query VoltAgent repo" >&2
    return 0
  }

  local cats=()
  if [[ -n "$CATEGORY" ]]; then
    cats=("$CATEGORY")
  else
    cats=("${VOLTAGENT_CATEGORIES[@]}")
  fi

  local cat entry name description
  for cat in "${cats[@]}"; do
    # Returns lines of: "NAME\tDESCRIPTION" (description may be empty if fetch fails).
    # We only list names here — detailed description would require per-file fetch.
    while IFS= read -r name; do
      [[ -z "$name" ]] && continue
      # name is file basename without .md
      if matches_keyword "$name"; then
        printf 'voltagent%s%s%s%s%s%s%s%s\n' "$US" "$name" "$US" "" "$US" "$cat" "$US" ""
      fi
    done < <(
      gh api "repos/${VOLTAGENT_REPO}/contents/categories/${cat}" \
        --jq '.[] | select(.type=="file" and (.name | endswith(".md")) and .name != "README.md") | .name | sub(".md$"; "")' \
        2>/dev/null || true
    )
  done
}

emit_text() {
  local source name desc ref model
  while IFS="$US" read -r source name desc ref model; do
    if [[ "$source" == "local" ]]; then
      printf '[local] %-28s %s\n' "$name" "${desc:-<no description>}"
      [[ -n "$model" ]] && printf '          %-28s model: %s\n' "" "$model"
    else
      printf '[volt]  %-28s (category: %s)\n' "$name" "$ref"
    fi
  done
}

emit_json() {
  local first=1
  printf '{"agents":['
  local source name desc ref model
  while IFS="$US" read -r source name desc ref model; do
    [[ $first -eq 0 ]] && printf ','
    first=0
    if [[ "$source" == "local" ]]; then
      printf '{"source":"local","name":%s,"description":%s,"path":%s,"model":%s}' \
        "$(json_escape "$name")" "$(json_escape "$desc")" "$(json_escape "$ref")" "$(json_escape "$model")"
    else
      printf '{"source":"voltagent","name":%s,"category":%s}' \
        "$(json_escape "$name")" "$(json_escape "$ref")"
    fi
  done
  printf ']}\n'
}

{
  case "$SOURCE" in
    local)     collect_local ;;
    voltagent) collect_voltagent ;;
    all)       collect_local; collect_voltagent ;;
  esac
} | {
  if [[ $JSON -eq 1 ]]; then
    emit_json
  else
    emit_text
  fi
}

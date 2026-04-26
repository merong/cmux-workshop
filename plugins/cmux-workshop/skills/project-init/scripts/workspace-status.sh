#!/usr/bin/env bash
# workspace-status.sh — cmux workspace 에이전트 상태 조회
# Usage: bash workspace-status.sh [--db /path/to/project.db]
#
# .claude/project.db의 agents 테이블과 live cmux tree를 교차 검증하여
# 각 에이전트의 실행 상태를 JSON으로 출력한다.
#
# Environment:
#   CMUX_WORKSHOP_DB_PATH      DB path override (default: ${PWD}/.claude/project.db)
#   CMUX_WORKSPACE_ID   must be set (we must be inside cmux)
#
# Exit codes:
#   0 — 성공
#   1 — cmux 미실행 / unreachable / project.db 없음

set -euo pipefail

DB_PATH="${CMUX_WORKSHOP_DB_PATH:-${PWD}/.claude/project.db}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --db) DB_PATH="$2"; shift 2 ;;
    --help|-h) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

# ── cmux 환경 확인 ──────────────────────────────────────────────
if [ -z "${CMUX_WORKSPACE_ID:-}" ]; then
  echo '{"error":"NOT_IN_CMUX","message":"CMUX_WORKSPACE_ID not set"}' >&2
  exit 1
fi

if ! cmux ping >/dev/null 2>&1; then
  echo '{"error":"CMUX_UNREACHABLE","message":"cmux ping failed"}' >&2
  exit 1
fi

# ── project.db 확인 ────────────────────────────────────────────
if [ ! -f "$DB_PATH" ]; then
  echo "{\"error\":\"NO_PROJECT_DB\",\"message\":\"$DB_PATH not found\"}" >&2
  exit 1
fi

command -v sqlite3 >/dev/null || {
  echo '{"error":"NO_SQLITE3","message":"sqlite3 not installed"}' >&2
  exit 1
}

# ── 데이터 수집 ─────────────────────────────────────────────────
PROJECT_JSON=$(sqlite3 "$DB_PATH" <<'EOF'
.mode json
SELECT name FROM project WHERE id = 1;
EOF
)

AGENTS_JSON=$(sqlite3 "$DB_PATH" <<'EOF'
.mode json
SELECT id, name, role, launch_command, is_caller FROM agents
ORDER BY is_caller DESC, position ASC;
EOF
)

HAS_SESSION_COLUMNS=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM pragma_table_info('local_surfaces') WHERE name = 'cli_session_id';")
if [ "$HAS_SESSION_COLUMNS" = "1" ]; then
  SURFACES_JSON=$(sqlite3 "$DB_PATH" <<'EOF'
.mode json
SELECT agent_id,
       status,
       cli_session_id,
       cli_session_label,
       last_active_at
FROM local_surfaces;
EOF
)
else
  SURFACES_JSON=$(sqlite3 "$DB_PATH" <<'EOF'
.mode json
SELECT agent_id,
       status,
       NULL AS cli_session_id,
       NULL AS cli_session_label,
       NULL AS last_active_at
FROM local_surfaces;
EOF
)
fi

TREE_JSON=$(cmux tree --json 2>/dev/null)

# ── python3으로 교차 검증 ──────────────────────────────────────
export PROJECT_JSON AGENTS_JSON SURFACES_JSON TREE_JSON

python3 <<'PY'
import json, os

project_list = json.loads(os.environ.get('PROJECT_JSON') or '[]')
agents = json.loads(os.environ.get('AGENTS_JSON') or '[]')
surfaces = json.loads(os.environ.get('SURFACES_JSON') or '[]')
tree = json.loads(os.environ.get('TREE_JSON') or '{}')

project_name = project_list[0]['name'] if project_list else ''
caller_surface = os.environ.get('CMUX_SURFACE_ID', '')
surface_state = {s.get('agent_id'): s for s in surfaces}

# tree에서 현재 workspace의 모든 surface title 추출
surface_titles = {}
for w in tree.get('windows', []):
    for ws in w.get('workspaces', []):
        if not ws.get('selected'):
            continue
        for p in ws.get('panes', []):
            for s in p.get('surfaces', []):
                title = s.get('title', '')
                surface_titles[title] = {
                    'surface_ref': s.get('ref', ''),
                    'pane_ref': p.get('ref', ''),
                    'here': s.get('here', False),
                }

agents_status = []
for a in agents:
    name = a.get('name', '')
    agent_id = a.get('id', '')
    is_caller = bool(a.get('is_caller'))
    prior = surface_state.get(agent_id, {})

    if is_caller:
        status = 'running'
        surface_ref = caller_surface
        pane_ref = ''
        for info in surface_titles.values():
            if info.get('here'):
                surface_ref = info['surface_ref']
                pane_ref = info['pane_ref']
                break
    elif name in surface_titles:
        status = prior.get('status') or 'running'
        surface_ref = surface_titles[name]['surface_ref']
        pane_ref = surface_titles[name]['pane_ref']
    else:
        status = 'missing'
        surface_ref = None
        pane_ref = None

    agents_status.append({
        'id': agent_id,
        'name': name,
        'role': a.get('role', ''),
        'status': status,
        'surface_ref': surface_ref,
        'pane_ref': pane_ref,
        'command': a.get('launch_command'),
        'session_id': prior.get('cli_session_id'),
        'session_label': prior.get('cli_session_label'),
        'session_prefix': (prior.get('cli_session_id') or '')[:8] or None,
        'last_active_at': prior.get('last_active_at'),
    })

result = {
    'project': project_name,
    'workspace_ref': tree.get('caller', {}).get('workspace_ref', ''),
    'agents': agents_status,
    'total': len(agents_status),
    'running': sum(1 for x in agents_status if x['status'] == 'running'),
    'missing': sum(1 for x in agents_status if x['status'] == 'missing'),
}
print(json.dumps(result, indent=2, ensure_ascii=False))
PY

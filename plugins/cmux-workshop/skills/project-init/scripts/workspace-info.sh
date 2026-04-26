#!/usr/bin/env bash
# workspace-info.sh — cmux workspace 상세 정보 조회
# Usage: bash workspace-info.sh
#
# 현재 cmux workspace의 전체 구조를 조회하여
# window, workspace, pane, surface 정보를 정리된 JSON으로 출력한다.
#
# Exit codes:
#   0 — 성공
#   1 — cmux 미실행

set -euo pipefail

# ── cmux 환경 확인 ──────────────────────────────────────────────
if [ -z "${CMUX_WORKSPACE_ID:-}" ]; then
  echo '{"error":"NOT_IN_CMUX","message":"CMUX_WORKSPACE_ID not set"}' >&2
  exit 1
fi

if ! cmux ping >/dev/null 2>&1; then
  echo '{"error":"CMUX_UNREACHABLE","message":"cmux ping failed"}' >&2
  exit 1
fi

# ── 정보 수집 ──────────────────────────────────────────────────
TREE_JSON=$(cmux tree --json 2>/dev/null)

# ── python3으로 요약 생성 ──────────────────────────────────────
python3 -c "
import json, os

tree = json.loads('''$TREE_JSON''')

caller_ws_ref = os.environ.get('CMUX_WORKSPACE_ID', '')
caller_sf_ref = os.environ.get('CMUX_SURFACE_ID', '')

# 현재 workspace 찾기
current_ws = None
for w in tree.get('windows', []):
    for ws in w.get('workspaces', []):
        if ws.get('selected'):
            current_ws = ws
            break
    if current_ws:
        break

if not current_ws:
    print(json.dumps({'error': 'NO_SELECTED_WORKSPACE'}))
    exit(0)

# pane & surface 요약
panes_info = []
for p in current_ws.get('panes', []):
    surfaces = []
    for s in p.get('surfaces', []):
        surfaces.append({
            'ref': s.get('ref', ''),
            'type': s.get('type', ''),
            'title': s.get('title', ''),
            'selected': s.get('selected', False),
            'here': s.get('here', False),
            'url': s.get('url')
        })
    panes_info.append({
        'ref': p.get('ref', ''),
        'focused': p.get('focused', False),
        'surface_count': len(surfaces),
        'surfaces': surfaces
    })

# caller 정보
caller = tree.get('caller', {})

result = {
    'workspace': {
        'ref': current_ws.get('ref', ''),
        'title': current_ws.get('title', ''),
        'pane_count': len(panes_info),
        'total_surfaces': sum(p['surface_count'] for p in panes_info)
    },
    'caller': {
        'workspace_ref': caller.get('workspace_ref', caller_ws_ref),
        'surface_ref': caller.get('surface_ref', caller_sf_ref)
    },
    'panes': panes_info,
    'environment': {
        'CMUX_WORKSPACE_ID': caller_ws_ref,
        'CMUX_SURFACE_ID': caller_sf_ref,
        'CMUX_SOCKET_PATH': os.environ.get('CMUX_SOCKET_PATH', '~/Library/Application Support/cmux/cmux.sock')
    }
}

print(json.dumps(result, indent=2, ensure_ascii=False))
"

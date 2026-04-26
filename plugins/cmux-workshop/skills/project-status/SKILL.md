---
name: project-status
description: >
  Show current project workflow progress and runtime agent status.
  Trigger on "project status", "project:status", "프로젝트 상태",
  "에이전트 상태", "workspace status", "워크스페이스 상태",
  "show agents", "에이전트 보여줘", "who is running", "뭐가 돌아가고 있어",
  "agent status", "프로젝트 에이전트 확인", "프로젝트 진행 상태",
  "project progress", "phase 확인".
  Displays progress phases (PRD / Agents / Deployed) and, if deployed,
  cross-references .claude/project.db with live cmux tree and saved CLI
  session metadata.
  Auto-migrates project.db schema/project_info for legacy projects on read.
version: 0.5.2
---

# Project Status

프로젝트의 워크플로우 진행 단계와 (배포된 경우) 에이전트 런타임 상태를 표시한다. 어느 단계에서든 실행 가능하며, 다음에 실행할 스킬을 안내한다.

## cmux-workshop Project Workflow

이 스킬은 모든 단계에서 실행 가능하다:

| Phase | Skill | 역할 |
|-------|-------|------|
| 1 | `project:init` | PRD 작성 |
| 2 | `project:agent` | AI 에이전트 팀 설계 |
| 3 | `project:reload` | cmux 워크스페이스에 배포 |
| - | **`project:status`** ← 현재 스킬 | 진행 상태 확인 |

## Prerequisites (선결조건)

- 없음 (모든 상태에서 실행 가능)
- `.claude/project.db`가 없으면 그에 맞게 가이드만 표시
- DB가 있지만 `project_info`가 없으면 자동으로 `project-info-capture.sh`를 실행하여 migration한 뒤 조회 (공통 규칙)

```bash
DB="${CLAUDE_PLUGIN_ROOT}/tools/db.sh"
CAPTURE="${CLAUDE_PLUGIN_ROOT}/tools/scripts/project-info-capture.sh"

if "$DB" exists; then
    "$DB" migrate
    HAS_INFO=$("$DB" scalar "SELECT COUNT(*) FROM project_info WHERE id = 1")
    if [[ "$HAS_INFO" != "1" ]]; then
        "$CAPTURE" --quiet
    fi
fi
```

## Resources

- [cmux CLI Reference](../project-init/references/cmux-cli-reference.md)
- [workspace-status.sh](../project-init/scripts/workspace-status.sh)

## Workflow

### Step 1: Read project.db

```bash
DB="${CLAUDE_PLUGIN_ROOT}/tools/db.sh"
"$DB" exists || { echo "NO_PROJECT_DB"; exit 0; }
```

**`NO_PROJECT_DB`인 경우:**

```
❌ 프로젝트가 초기화되지 않았습니다.

진행 단계:
  [  ] 1. PRD 작성            ← 여기부터 시작
  [  ] 2. 에이전트 설계
  [  ] 3. cmux 배포

👉 다음 단계: `project:init`으로 프로젝트를 시작하세요.
```

중단.

DB가 존재하면 다음 쿼리로 상태 수집:

```bash
# 프로젝트 메타
"$DB" json "$(cat "${CLAUDE_PLUGIN_ROOT}/tools/queries/get-project.sql")"

# 3단계 progress
"$DB" json "$(cat "${CLAUDE_PLUGIN_ROOT}/tools/queries/get-progress.sql")"

# PRD 포인터
"$DB" json "SELECT path, created_at FROM prd WHERE id=1"

# 에이전트 (있으면)
"$DB" json "$(cat "${CLAUDE_PLUGIN_ROOT}/tools/queries/get-agents.sql")"

# Layout splits (있으면)
"$DB" json "$(cat "${CLAUDE_PLUGIN_ROOT}/tools/queries/get-layout.sql")"

# Runtime surfaces + saved CLI session metadata (있으면)
"$DB" json "$(cat "${CLAUDE_PLUGIN_ROOT}/tools/queries/get-surfaces.sql")"
```

### Step 2: Determine current phase

`progress` 테이블의 `completed` 값(0/1)으로 현재 단계를 판정:

| 조건 | 현재 단계 | 다음 스킬 |
|------|-----------|-----------|
| `prd = 0` | **Phase 1 (PRD 작성 중)** | `project:init` |
| `prd = 1 && agents = 0` | **Phase 2 (에이전트 설계 필요)** | `project:agent` |
| `agents = 1 && deployed = 0` | **Phase 3 (cmux 배포 필요)** | `project:reload` |
| 모두 `1` | **모두 완료 (운영 중)** | 런타임 상태 확인 |

### Step 3: Display progress overview

공통 헤더:

```
프로젝트: {name}
설명: {description}
설정 파일: .claude/project.db (SQLite)

진행 단계:
  [{prd_mark}] 1. PRD 작성           {prd_detail}
  [{agents_mark}] 2. 에이전트 설계    {agents_detail}
  [{deployed_mark}] 3. cmux 배포      {deployed_detail}
```

- `mark`: `✅` (완료) / ` ` (미완료)
- `detail`:
  - PRD: `({prd.path}, {prd.created_at})` 또는 빈 값
  - Agents: `({N}명 설계됨, {progress.agents.completed_at})` 또는 빈 값
  - Deployed: `({progress.deployed.completed_at})` 또는 빈 값

### Step 4: Phase-specific details

#### Phase 1 (PRD 미완료)

```
👉 다음 단계: `project:init`으로 PRD를 작성하세요.
```

중단.

#### Phase 2 (에이전트 미설계)

PRD 내용을 간단히 미리보기 (선택):

```bash
head -10 .claude/PRD.md 2>/dev/null
```

```
PRD 미리보기:
  (첫 몇 줄)

👉 다음 단계: `project:agent`로 AI 에이전트 팀을 설계하세요.
```

중단.

#### Phase 3 (에이전트 설계 완료, 미배포)

설계된 에이전트 표시:

```
설계된 에이전트:
┌──────────────┬─────────────────┬─────────────────┬──────────┐
│ Agent        │ Model           │ Role            │ Type     │
├──────────────┼─────────────────┼─────────────────┼──────────┤
│ Claude       │ Claude Opus 4.6 │ orchestrator    │ caller   │
│ Implementer  │ GPT-5.4         │ 코드 구현        │ codex    │
│ Reviewer     │ GPT-5.x         │ 코드 리뷰        │ codex    │
└──────────────┴─────────────────┴─────────────────┴──────────┘

👉 다음 단계: `project:reload`로 cmux에 에이전트를 배포하세요.
   (cmux 내부 터미널에서 실행해야 합니다.)
```

중단.

#### Phase 완료 (런타임 모드)

Step 5로 진행하여 실제 cmux 상태를 확인한다.

### Step 5: Runtime status check (Phase 완료 시만)

```bash
if [ -z "${CMUX_WORKSPACE_ID:-}" ]; then echo "NOT_IN_CMUX"; else cmux ping && echo "CMUX_OK"; fi
```

**`NOT_IN_CMUX`인 경우:**

```
⚠️ cmux 외부에서 실행 중입니다. 런타임 상태는 확인할 수 없습니다.
   (진행 단계만 위에 표시됨)

cmux 안에서 실행하면 에이전트 실행 상태도 확인할 수 있습니다.
```

중단.

### Step 6: Get live tree and build runtime status

**빠른 경로 (스크립트 사용 가능 시):**

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/project-init/scripts/workspace-status.sh"
```

스크립트는 `.claude/project.db`의 `agents`/`local_surfaces` 테이블을 읽어 live
cmux tree와 교차 검증하고 session prefix를 포함한 JSON을 stdout에 출력한다.
Step 7로.

**수동 경로:**

```bash
cmux tree --json
DB="${CLAUDE_PLUGIN_ROOT}/tools/db.sh"
"$DB" json "$(cat "${CLAUDE_PLUGIN_ROOT}/tools/queries/get-agents.sql")"
"$DB" json "$(cat "${CLAUDE_PLUGIN_ROOT}/tools/queries/get-surfaces.sql")"
```

각 에이전트에 대해:
- **Caller** (`is_caller = 1`): 항상 `running` (현재 스킬을 실행 중)
- **Non-caller**: workspace의 surface `title`이 `agent.name`과 일치하는지 검색
  - 일치 → `local_surfaces.status`를 그대로 사용 (`running` / `error` / `skipped`)
  - 불일치 → `missing`
- `cli_session_id`, `last_active_at`을 함께 보관한다. 표시는 `cli_session_id` 8자 prefix 또는 `∅`로 축약한다.

**선택적 on-demand readiness 재검증:**

사용자가 `--verify` 플래그 의도(프롬프트로 "상태 실제로 확인해줘" 등)를 드러내면
각 `running` 에이전트에 대해 `verify-pane-ready.sh`를 한 번 더 돌려 `local_surfaces.status`를 갱신한다.
그렇지 않으면 DB에 기록된 값을 그대로 믿는다 (매번 read-screen을 돌리면 사용자 화면이 깜빡거리고 느려짐).

```bash
VERIFY="${CLAUDE_PLUGIN_ROOT}/skills/project-reload/scripts/verify-pane-ready.sh"
# verify 요청 시에만 실행 — 기본은 DB 값 사용
```

### Step 7: Display runtime status report

```
워크스페이스: {workspace_ref}

┌──────────────┬──────────┬─────────────┬──────────┬──────────────────────────────┐
│ Agent        │ Status   │ Surface     │ Session  │ Command                      │
├──────────────┼──────────┼─────────────┼──────────┼──────────────────────────────┤
│ Claude       │ running  │ surface:1   │ ∅        │ (caller)                     │
│ Implementer  │ running  │ surface:3   │ a1b2c3d4 │ codex --full-auto            │
│ Reviewer     │ error    │ surface:4   │ a1b2c3d4 │ codex --full-auto            │
│ Tester       │ missing  │ —           │ ∅        │ (missing)                    │
└──────────────┴──────────┴─────────────┴──────────┴──────────────────────────────┘

status 범례: running=정상 / error=초기화 실패(사용자 개입 필요) /
            skipped=CLI 미설치 / missing=pane 없음
session: `cli_session_id` 8자 prefix, `∅`=미지원/미캡처

레이아웃:
┌─────────────────┬─────────────────┐
│                 │ Implementer ✅   │
│  Claude (현재)   │                 │
│                 ├─────────────────┤
│                 │ Reviewer ❌      │
└─────────────────┴─────────────────┘
```

### Step 8: Actionable guidance

상태별 안내:

| 상황 | 안내 |
|------|------|
| 모두 running | `모든 에이전트가 실행 중입니다.` |
| 일부 missing | `누락된 에이전트를 복원하려면 \`project:reload\`를 사용하세요.` |
| 모두 missing | `모든 에이전트가 실행되지 않고 있습니다. \`project:reload\`로 배포하세요.` |
| local_surfaces 비어 있거나 outdated | `런타임 상태를 갱신하려면 \`project:reload\`를 실행하세요.` |
| 에이전트 설계 변경이 필요 | `에이전트를 추가/수정하려면 \`project:agent\`를 실행하세요.` |
| `error` 상태 존재 | `해당 pane으로 이동해 직접 수습(로그인/재실행 등)한 뒤 \`project:reload\`를 다시 실행하세요. 어떤 에이전트가 실패했는지는 위 표 참조.` |

## Design Notes

- **Progress 먼저, Runtime 다음**: 항상 진행 단계부터 표시. 런타임 체크는 Phase 완료 시에만.
- **비cmux 환경 지원**: 진행 단계 조회는 cmux 없이도 가능. 런타임 상태만 cmux 필요.
- **Session visibility**: `project:reload`가 기록한 `cli_session_id` prefix와 `last_active_at`을 읽어 resume 가능성을 빠르게 확인한다.
- **Read-only after migration**: 오래된 DB는 조회 전 `db.sh migrate`/`project-info-capture.sh`로 스키마와 위치 정보를 보정한다. 그 뒤에는 상태 표시만 수행한다.

## Edge Cases

- **project.db 없음**: Phase 1 미시작 안내만 표시
- **schema_version mismatch**: `project.schema_version`이 기대치와 다르면 경고하되 best-effort로 읽는다
- **cmux 미실행**: Progress 표시 후 런타임은 skip
- **워크스페이스 외부 (CMUX_WORKSPACE_ID 없음)**: Progress만 표시, 경고
- **surface title이 다름 (수동 변경)**: title 정확 일치로만 감지. 불일치 시 missing으로 표시

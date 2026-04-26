---
name: project-reload
description: >
  Deploy or restore project agents to cmux workspace (phase 3 of 3).
  Trigger on "project reload", "project:reload", "project deploy", "project:deploy",
  "프로젝트 리로드", "프로젝트 복원", "프로젝트 배포", "reload workspace",
  "워크스페이스 복원", "restore agents", "에이전트 복원", "에이전트 배포",
  "reload agents", "에이전트 재시작", "워크스페이스 재생성", "project reconnect",
  "에이전트 다시 띄워", "프로젝트 다시 시작", "deploy agents", "cmux 배포".
  Requires agents phase completed (project:agent must run first).
  Auto-migrates project.db schema/project_info for legacy projects before any read/write.
  Reads agents + layout_splits from .claude/project.db, creates/restores missing
  cmux panes, resumes saved Claude/Codex CLI sessions when possible, upserts
  local_workspace + local_surfaces, and marks progress.deployed.
version: 0.7.1
---

# Project Reload — cmux 배포 / 복원

프로젝트의 **3단계** 스킬. `.claude/project.db`의 에이전트 구성을 cmux 워크스페이스에 배포한다. 초기 배포와 cmux 재시작 후 복원을 **같은 로직**으로 처리한다.

## cmux-workshop Project Workflow

| Phase | Skill | 역할 |
|-------|-------|------|
| 1 | `project:init` | PRD 작성 |
| 2 | `project:agent` | AI 에이전트 팀 설계 |
| **3** | **`project:reload`** ← 현재 스킬 | cmux 워크스페이스에 배포/복원 |

## Prerequisites (선결조건)

**반드시 만족해야 할 조건:**

1. `.claude/project.db`가 존재 (`tools/db.sh exists`)
2. `progress.prd.completed = 1`
3. `progress.agents.completed = 1`
4. `project_info` 행이 존재 — **없으면 migration 강제**
5. cmux가 실행 중이고 현재 터미널이 cmux 내부 (`CMUX_WORKSPACE_ID` 환경변수)

**선결조건 불충족 시 동작:**

```bash
DB="${CLAUDE_PLUGIN_ROOT}/tools/db.sh"
CAPTURE="${CLAUDE_PLUGIN_ROOT}/tools/scripts/project-info-capture.sh"

"$DB" exists || { echo "NO_PROJECT_DB"; exit 1; }
"$DB" migrate
"$DB" json "$(cat "${CLAUDE_PLUGIN_ROOT}/tools/queries/get-progress.sql")"

# project_info bootstrap (공통 규칙)
HAS_INFO=$("$DB" scalar "SELECT COUNT(*) FROM project_info WHERE id = 1")
if [[ "$HAS_INFO" != "1" ]]; then
    "$CAPTURE" --quiet
elif [[ "$("$DB" scalar "SELECT project_root FROM project_info WHERE id=1")" != "$PWD" ]]; then
    "$CAPTURE" --quiet
fi
```

| 상태 | 동작 |
|------|------|
| `NO_PROJECT_DB` | "프로젝트가 초기화되지 않았습니다. `project:init`을 먼저 실행하세요." → **중단** |
| `progress.prd.completed != 1` | "PRD가 없습니다. `project:init`을 먼저 완료하세요." → **중단** |
| `progress.agents.completed != 1` | "에이전트 설계가 완료되지 않았습니다. `project:agent`를 먼저 실행하세요." → **중단** |
| `project_info` 비어 있음 / project_root 불일치 | **중단하지 않음** — `project-info-capture.sh` 자동 실행 후 계속 진행 |
| `CMUX_WORKSPACE_ID` 없음 | "cmux workspace 안에서 실행해야 합니다." → **중단** |
| `cmux ping` 실패 | "cmux가 응답하지 않습니다. cmux를 먼저 실행하세요." → **중단** |
| 프로젝트 루트 `AGENTS.md` 없음 | **중단하지 않음** — 플러그인에서 자동 복사 후 계속 진행 (아래 참조) |

**AGENTS.md bootstrap (에이전트 공통 규범 보장):**

```bash
if [[ ! -f "./AGENTS.md" ]]; then
  PLUGIN_AGENTS_MD="${CLAUDE_PLUGIN_ROOT}/../../AGENTS.md"
  [[ -f "$PLUGIN_AGENTS_MD" ]] || PLUGIN_AGENTS_MD="${CLAUDE_PLUGIN_ROOT}/AGENTS.md"
  if [[ -f "$PLUGIN_AGENTS_MD" ]]; then
    cp "$PLUGIN_AGENTS_MD" ./AGENTS.md
    echo "→ AGENTS.md를 프로젝트 루트에 복원했습니다 (에이전트 공통 규범)."
  else
    echo "⚠️ 플러그인 AGENTS.md를 찾을 수 없습니다. 공통 규범 없이 배포합니다." >&2
  fi
fi
```

> **이유**: specialist CLI들은 CWD에서 `AGENTS.md`를 자동 로드한다. 이 파일이
> 없으면 표준 Hand-off/Report 형식과 파괴적 작업 규칙이 적용되지 않아
> 협업 프로토콜이 붕괴한다. 배포 직전에 복원하여 모든 pane이 동일한 규범을
> 공유하도록 보장한다.

모든 조건 충족 시 Step 1로 진행.

## Operating Modes

이 스킬은 두 시나리오를 구분 없이 처리한다:

- **Initial Deployment**: `progress.deployed.completed = 0` → 모든 에이전트가 새로 생성됨. 이전 `cli_session_id`가 없으면 각 CLI를 fresh launch한다.
- **Reload / Restoration**: `progress.deployed.completed = 1` → 이미 실행 중인 에이전트는 유지, 누락된 것만 재생성한다. 저장된 Claude/Codex `cli_session_id`가 있으면 fresh launch 대신 resume 명령을 합성한다.

동작 로직은 동일하다. 현재 `cmux tree`와 `project.db`의 `agents`/`layout_splits`/`local_surfaces` 세션 메타데이터를 비교하여 필요한 pane만 생성한다.

## Resources

- [cmux CLI Reference](../project-init/references/cmux-cli-reference.md)
- [workspace-status.sh](../project-init/scripts/workspace-status.sh)

## Workflow

### Step 1: Check prerequisites

선결조건 섹션의 모든 항목을 확인. 실패 시 해당 안내 후 중단.

### Step 2: Verify cmux

```bash
if [ -z "${CMUX_WORKSPACE_ID:-}" ]; then echo "NOT_IN_CMUX"; else cmux ping && echo "CMUX_OK"; fi
```

### Step 3: Read agents + layout from project.db

```bash
DB="${CLAUDE_PLUGIN_ROOT}/tools/db.sh"

# Agents in display order (caller first)
"$DB" json "$(cat "${CLAUDE_PLUGIN_ROOT}/tools/queries/get-agents.sql")"

# Layout splits in execution order
"$DB" json "$(cat "${CLAUDE_PLUGIN_ROOT}/tools/queries/get-layout.sql")"

# Prior runtime/session state keyed by agent_id. Keep this in memory as
# prior_state[agent.id] before reset-local.sql wipes local_surfaces in Step 7.
"$DB" json "SELECT agent_id, surface_id, pane_id, tab_title, status,
                   cli_session_id, cli_session_label, last_active_at
              FROM local_surfaces"

# For logging only — current deployed flag
"$DB" scalar "SELECT completed FROM progress WHERE phase='deployed'"
```

`prior_state`는 아래 용도로 사용한다:
- EXISTING pane은 launch하지 않고 기존 `cli_session_id`/`cli_session_label`을 보존한다.
- 누락 pane 생성 시 Claude/Codex `cli_session_id`가 있으면 resume 명령으로 대체한다.
- Step 7에서 `reset-local.sql` 후 재 INSERT할 세션 값을 복원한다.

### Step 4: Check CLI availability

각 non-caller 에이전트의 `cli_binary`에 대해:

```bash
command -v codex &>/dev/null && echo "codex:available" || echo "codex:missing"
command -v claude &>/dev/null && echo "claude:available" || echo "claude:missing"
```

Missing인 경우 경고하되 진행한다 (해당 에이전트는 `skipped` 상태로 기록 — `local_surfaces.status = 'skipped'`).

### Step 4.5: Compose effective launch commands

누락 pane을 새로 만들 때 사용할 `effective_launch_command`를 에이전트별로 미리 합성한다. 기존 pane(`EXISTING`)은 다시 launch하지 않지만, Step 7에서 이전 session metadata를 그대로 보존한다.

규칙:

```bash
session_id="$(prior_state_lookup "$agent_id" cli_session_id)"   # empty when absent
effective_launch_command="$agent_launch_command"
launch_mode="fresh"

if [[ -n "$session_id" && "$agent_type" == "claude" ]]; then
  sid_q=$(printf '%q' "$session_id")
  # 세션 파일이 사라졌으면 resume하지 않고 fresh launch로 fallback한다.
  enc=$(python3 -c 'import sys,os; p=os.path.realpath(sys.argv[1]); print("-"+p.replace("/","-"))' "$PWD")
  if [[ -f "$HOME/.claude/projects/$enc/$session_id.jsonl" ]]; then
    effective_launch_command="claude --resume $sid_q"
    launch_mode="resume"
  else
    echo "  ⚠️  $agent_name — saved Claude session $session_id not found; fresh launch" >&2
  fi
elif [[ -n "$session_id" && "$agent_type" == "codex" ]]; then
  sid_q=$(printf '%q' "$session_id")
  if find "$HOME/.codex/sessions" -name "$session_id" -o -name "$session_id.*" 2>/dev/null | grep -q .; then
    effective_launch_command="codex resume $sid_q"
    launch_mode="resume"
  else
    echo "  ⚠️  $agent_name — saved Codex session $session_id not found; fresh launch" >&2
  fi
fi

if [[ "$launch_mode" == "resume" ]]; then
  echo "  → $agent_name resuming session ${session_id:0:12}..."
else
  echo "  → $agent_name starting fresh"
fi
```

- `session_id`는 반드시 shell-quote한다.
- `custom` 또는 `cli_session_id IS NULL`이면 `agent.launch_command`를 그대로 사용한다.
- resume으로 launch한 경우에도 Step 6.10에서 다시 session id를 캡처한다. CLI가 새 session 파일을 만들 수 있기 때문이다.

### Step 5: Get workspace tree and build status map

```bash
cmux tree --json
```

파싱 결과:

1. **Caller info**:
   - `caller.surface_ref` — Claude가 실행 중인 surface (또는 `here: true`인 surface)
   - `here: true`인 surface의 부모 pane `ref` — Step 9에서 포커스 복귀용

2. **Agent status map** — 각 non-caller 에이전트에 대해:
   - 현재 workspace(`selected: true`)의 모든 surface `title` 스캔
   - `title === agent.name`인 surface 발견 → `EXISTING` (surface_ref 기록, launch skip, 기존 `cli_session_id` 유지)
   - 없음 → `NEEDS_CREATION`

3. **상태 리포트 표시**:

```
프로젝트 에이전트 상태:
  Claude       — ✅ caller (surface:1)
  Implementer  — ✅ 실행 중 (surface:3)
  Reviewer     — ❌ 없음 → 생성 예정
```

모든 non-caller 에이전트가 EXISTING이면: launch/resume 없이 local_workspace / local_surfaces만 갱신하고 중단 (아래 Step 7~9 실행, Step 6 skip). 이때 각 row는 `prior_state`의 `cli_session_id`/`cli_session_label`을 유지하고 `last_active_at=datetime('now')`만 갱신한다.

### Step 6: Create missing agent panes

Initialize `surface_map`:
- `surface_map["claude"] = caller.surface_ref`
- 각 EXISTING 에이전트: `surface_map[agent.id] = existing_surface_ref`

For each split in `layout.splits` (순서대로):

1. **Find agent**: `split.agent_id`로 `agents`에서 찾기
2. **Skip if existing**: `surface_map[agent.id]`가 이미 있으면 다음으로
3. **Skip if CLI missing**: `agent.cli_binary`가 missing이면 status = `"skipped"`, 다음으로
4. **Resolve `from`**: `from_ref = surface_map[split.from]`
   - Resolve 실패 시 (의존 에이전트가 skipped) → 에러 로그 후 해당 에이전트도 skip
5. **Create split**:

```bash
cmux new-split <split.direction> --surface <from_ref>
```

출력 `OK surface:N workspace:M`에서 `surface:N` 추출:
```bash
echo "$OUTPUT" | grep -o 'surface:[0-9]*'
```

6. **Launch agent**:

```bash
sleep 0.5
cmux send --surface <new_surface_ref> "$effective_launch_command"
cmux send-key --surface <new_surface_ref> enter     # ← 반드시 필요
```

> **주의 — `cmux send`는 엔터를 보내지 않는다.** 입력 버퍼에 텍스트만 쌓을
> 뿐이므로, 셸이든 TUI CLI(Claude Code/Codex)든 **반드시 뒤이어
> `cmux send-key enter`를 호출**해야 명령/메시지가 실제로 실행·전송된다.
> `\n`을 문자열에 붙이는 방식은 셸에서만 동작하고 TUI REPL에서는 무시된다.

7. **Label the pane**:

```bash
cmux rename-tab --surface <new_surface_ref> "<agent.name>"
```

8. **Inject persona from `agent.agent_file`** (신규 v0.3):

CLI가 프롬프트 입력 단계에 도달할 때까지 잠깐 대기한 뒤 `.claude/agents/{id}.md` 내용을 첫 메시지로 전송한다. **페르소나 본문 앞에 AGENTS.md 선행 안내를 붙여** 공통 규범이 개인 페르소나보다 먼저 적용되도록 한다.

```bash
if [ -n "$agent_file" ] && [ -f "$agent_file" ]; then
  sleep 2   # CLI 초기화 대기 (codex/claude가 REPL에 진입하는 시간)

  # AGENTS.md 선행 안내 (프로젝트 루트 파일을 읽도록 지시)
  PREAMBLE="프로젝트 루트의 'AGENTS.md'를 먼저 읽고, 거기 정의된 표준 Hand-off/Report 형식과 파괴적 작업 규칙을 엄수하라. 이 페르소나보다 AGENTS.md가 상위이다. 이어지는 페르소나 본문은 너의 역할 정의이다:"

  # Preamble + 페르소나 본문을 한 덩어리로 전송한 뒤 엔터로 submit
  cmux send --surface <new_surface_ref> "${PREAMBLE}

$(cat "$agent_file")"
  cmux send-key --surface <new_surface_ref> enter    # ← 반드시 필요 (TUI submit)
fi
```

**주입 규칙:**
- `agent.agent_file`이 없거나 파일이 존재하지 않으면 skip (경고 로그).
- caller(Claude)는 이미 페르소나가 로드되어 있으므로 주입하지 않는다 (`is_caller: true`는 skip).
- VoltAgent/Claude Code 표준 frontmatter도 함께 전송된다 — CLI가 무시하거나 컨텍스트로 해석한다.
- 주입 실패가 배포 실패로 이어지지 않는다: 에러 시 경고만 출력하고 pane은 계속 사용 가능.
- AGENTS.md preamble은 **파일 경로만 알리고 내용은 붙이지 않는다** — CLI가 CWD에서 자동 로드하거나 필요 시 읽는다. 컨텍스트 창 낭비 방지.
- **전송 완료를 위해 `send-key enter`가 필수**. 여러 줄 페르소나라도 엔터 한 번으로 submit된다 (복붙과 동일한 동작).

9. **Verify pane readiness** (신규 v0.5):

CLI가 실제로 REPL 준비 상태에 도달했는지 화면을 읽어 검증한다. 이 단계를 건너뛰면 CLI 설치/인증 실패나 크래시를 caller가 hand-off를 보낸 뒤에야 감지하게 된다.

```bash
VERIFY="${CLAUDE_PLUGIN_ROOT}/skills/project-reload/scripts/verify-pane-ready.sh"

result=$("$VERIFY" --surface "$new_surface_ref" --cli "$agent_type" --retries 10 --interval 1.5) || RC=$?
RC=${RC:-0}

case "$RC" in
  0)  # READY
    pane_status="running"
    echo "  ✅ $agent_name — ready ($new_surface_ref)"
    ;;
  1)  # NOT_READY (timeout, but no obvious error)
    pane_status="running"   # pane은 살아있음. 단, 초기화 미확인.
    ready_warning+=("$agent_name: $result")
    echo "  ⚠️  $agent_name — 초기화 확인 안 됨 (타임아웃). pane은 유지." >&2
    ;;
  2)  # ERROR pattern on screen
    pane_status="error"
    ready_warning+=("$agent_name: $result")
    echo "  ❌ $agent_name — 에러 화면 감지: ${result#ERROR * }" >&2
    ;;
  3|*) # script/cmux misuse
    pane_status="running"
    echo "  ⚠️  $agent_name — verify 스크립트 실행 실패 (무시하고 계속)" >&2
    ;;
esac
```

- `agent_type`은 `agents.type` 컬럼 값(`claude`/`codex`/`custom`).
- 이 검증 결과로 `local_surfaces.status`를 기록한다(`running` / `error`).
- **caller는 재시작/복원 대상이 아니므로 검증을 건너뛴다** (이미 이 스크립트를 실행 중인 pane이다).
- Skipped(CLI missing) 에이전트도 검증하지 않는다.

10. **Capture session id** (신규 v0.7):

readiness 검증 직후 Claude/Codex session id를 휴리스틱으로 캡처한다. 실패하면 `cli_session_id=NULL`을 유지하고 경고만 남긴다. resume launch였더라도 다시 캡처한다.

```bash
captured_session_id=""

case "$agent_type" in
  claude)
    enc=$(python3 -c 'import sys,os; p=os.path.realpath(sys.argv[1]); print("-"+p.replace("/","-"))' "$PWD")
    dir="$HOME/.claude/projects/$enc"
    captured_session_id=$(ls -t "$dir"/*.jsonl 2>/dev/null | head -1 | xargs -I{} basename {} .jsonl)
    ;;
  codex)
    captured_session_id=$(ls -t "$HOME/.codex/sessions" 2>/dev/null | head -1)
    ;;
  *)
    captured_session_id=""
    ;;
esac

if [[ -n "$captured_session_id" ]]; then
  session_id="$captured_session_id"
  session_label="$agent_name"
  last_active_expr="datetime('now')"
  echo "  → $agent_name session captured: ${session_id:0:12}..."
else
  session_id=""
  session_label=""
  last_active_expr="NULL"
  [[ "$agent_type" == "claude" || "$agent_type" == "codex" ]] \
    && echo "  ⚠️  $agent_name — session id capture failed; future reload will fresh launch" >&2
fi
```

- caller(`is_caller=1`)와 skipped pane은 이 단계를 건너뛴다.
- `last_active_at`은 캡처/관찰 성공 시 Step 7에서 `datetime('now')`로 기록한다.
- `cli_session_id`는 255자 이내 문자열로 취급하며 DB에는 `VARCHAR(255)` 컬럼에 저장한다.

11. **Update map**: `surface_map[agent.id] = new_surface_ref`

### Step 7: Refresh local_workspace + local_surfaces in project.db

**완전 교체** — 이전 ID는 모두 버리고 현재 cmux 상태를 반영.

```bash
DB="${CLAUDE_PLUGIN_ROOT}/tools/db.sh"

# Wipe machine-local zone (workspace, surfaces, kv)
"$DB" run "${CLAUDE_PLUGIN_ROOT}/tools/queries/reset-local.sql"

# Upsert workspace singleton
WSID=$("$DB" quote "<current workspace ref>")
CREATED=$("$DB" scalar "SELECT COALESCE((SELECT created_at FROM local_workspace WHERE id=1), datetime('now'))")
CREATED_Q=$("$DB" quote "$CREATED")

"$DB" exec "INSERT INTO local_workspace (id, workspace_id, created_at, updated_at)
            VALUES (1, $WSID, $CREATED_Q, datetime('now'))"

# Insert one local_surfaces row per agent (or use skill-local insert-surface.sql template)
for each agent in surface_map:
    AID=$("$DB" quote "<agent.id>")
    SID=$("$DB" quote "<surface_ref>")
    PID=$("$DB" quote "<pane_ref>")
    TTL=$("$DB" quote "<agent.name>")
    ST=$("$DB" quote "running")   # or 'skipped' / 'stopped'
    SESSION_ID=$("$DB" quote "<captured-or-prior-session-id>")      # or NULL
    SESSION_LABEL=$("$DB" quote "<agent.name>")                     # or NULL
    LAST_ACTIVE="datetime('now')"                                   # or NULL

    "$DB" exec "INSERT INTO local_surfaces (
                    agent_id, surface_id, pane_id, tab_title, status,
                    cli_session_id, cli_session_label, last_active_at, updated_at
                )
                VALUES (
                    $AID, $SID, $PID, $TTL, $ST,
                    $SESSION_ID, $SESSION_LABEL, $LAST_ACTIVE, datetime('now')
                )"
```

Skipped 에이전트: `status = 'skipped'`, `surface_id`/`pane_id`는 NULL로 INSERT한다
(빈 문자열 아님):

```bash
"$DB" exec "INSERT INTO local_surfaces (
                agent_id, surface_id, pane_id, tab_title, status,
                cli_session_id, cli_session_label, last_active_at, updated_at
            )
            VALUES ($AID, NULL, NULL, $TTL, 'skipped',
                    NULL, NULL, NULL, datetime('now'))"
```

Session 값 결정:
- `EXISTING`: `prior_state`의 `cli_session_id`/`cli_session_label`을 그대로 쓰고 `last_active_at=datetime('now')`로 갱신한다.
- 새로 생성 + 캡처 성공: Step 6.10에서 얻은 `session_id`, `agent.name`, `datetime('now')`를 기록한다.
- 새로 생성 + 캡처 실패: 세 session 컬럼을 모두 `NULL`로 둔다.
- `skipped`: 세 session 컬럼을 모두 `NULL`로 둔다.
- `error`: pane은 살아 있으므로 `surface_id`/`pane_id`는 기록한다. session capture가 성공했으면 기록하고, 실패했으면 `NULL`로 둔다.

**`status` 값 (v0.5+):**

| 값 | 의미 |
|----|------|
| `running` | pane 생성 + CLI 실행 + readiness 검증 통과 |
| `error` | Step 6.9 검증에서 에러 패턴 감지 (인증 실패, command not found 등) |
| `skipped` | `cli_binary`가 시스템에 없어 생성하지 않음 |
| `stopped` | (예약) — 과거에 running이었다가 종료된 상태 |

`error` 상태인 행도 `surface_id`/`pane_id`는 INSERT한다 (pane 자체는 살아있으므로 사용자가 직접 진입해 수습할 수 있다).

쿼리 템플릿 참조: `skills/project-reload/scripts/queries/`.

### Step 8: Update progress.deployed + project.updated_at

```bash
"$DB" exec "UPDATE progress
            SET completed = 1, completed_at = datetime('now')
            WHERE phase = 'deployed'"

"$DB" exec "UPDATE project SET updated_at = datetime('now') WHERE id = 1"
```

**모든 에이전트가 skipped**인 극단 케이스에는 `deployed.completed`를 `0`으로 유지
(UPDATE를 건너뛴다).

### Step 9: Verify reconstruction + aggregate readiness

**9a. 트리 구조 검증:**

```bash
cmux tree --json
```

각 에이전트의 `title`이 트리에 정확히 존재하는지 확인. 불일치 시 경고.

**9b. Aggregate readiness 재확인:**

Step 6.9에서 개별 검증한 결과를 종합한다. 누락된 상태(`ready_warning` 배열에 담긴 항목)가 있으면 **재검증을 한 번 더 수행**한다 — CLI 로딩이 느려 타임아웃되었을 수 있다.

```bash
VERIFY="${CLAUDE_PLUGIN_ROOT}/skills/project-reload/scripts/verify-pane-ready.sh"
DB="${CLAUDE_PLUGIN_ROOT}/tools/db.sh"

# 재검증 대상: Step 6.9에서 NOT_READY 또는 ERROR로 기록된 pane
for item in "${ready_warning[@]}"; do
  agent_id=$(echo "$item" | cut -d: -f1)
  surface_ref=$("$DB" scalar "SELECT surface_id FROM local_surfaces WHERE agent_id='$agent_id'")
  cli_type=$("$DB" scalar "SELECT type FROM agents WHERE id='$agent_id'")
  [[ -n "$surface_ref" && "$surface_ref" != "NULL" ]] || continue

  if "$VERIFY" --surface "$surface_ref" --cli "$cli_type" --retries 5 --interval 2.0 >/dev/null; then
    "$DB" exec "UPDATE local_surfaces
                SET status='running', last_active_at=datetime('now'), updated_at=datetime('now')
                WHERE agent_id='$agent_id'"
    echo "  ✅ $agent_id — 재검증 통과, status → running"
  else
    echo "  ⚠️  $agent_id — 재검증도 실패. status 유지."
  fi
done
```

모든 에이전트가 `running`이면 다음 Step으로. 하나라도 `error`/확인불가 상태면 그 pane을 Step 11 리포트에서 명시적으로 표시한다.

### Step 10: Return focus and notify

```bash
cmux focus-pane --pane <caller_pane_ref>
cmux notify --title "Project Deployed" --body "All agents running"
```

### Step 11: Report

리포트에는 각 에이전트의 **readiness 상태**와 session 표시를 명시한다:

- `✅ ready` — Step 6.9 또는 9b 검증 통과
- `⚠️ unverified` — pane은 살아있으나 ready 마커 미감지 (CLI가 느리게 로딩 중일 수 있음)
- `❌ error` — 검증에서 에러 패턴 감지 (사용자 개입 필요)
- `⏭ skipped` — CLI missing
- `session: a1b2c3d4…` — `cli_session_id`가 있을 때 8~12자 prefix 표시
- `session: ∅` — session 미지원/미캡처/스킵

**Initial deployment 시:**

```
✅ cmux 배포 완료

┌─────────────────┬─────────────────┐
│                 │ Implementer     │
│  Claude (현재)   │ [GPT-5.4]       │
│  [Opus 4.6]     ├─────────────────┤
│                 │ Reviewer        │
│                 │ [GPT-5.x]       │
└─────────────────┴─────────────────┘

에이전트 (readiness):
  Claude        — ✅ ready  (caller, surface:1, session: ∅)
  Implementer   — ✅ ready  [GPT-5.4]        (surface:3, session: a1b2c3d4…)
  Reviewer      — ⚠️ unverified [GPT-5.x] (surface:4, session: a1b2c3d4…) — 수동 확인 권장

진행 단계:
  [✅] 1. PRD 작성
  [✅] 2. 에이전트 설계
  [✅] 3. cmux 배포 완료

상태 확인: `project:status`
```

하나라도 `❌ error`가 있으면 해결 가이드를 함께 출력:

```
❌ 일부 에이전트가 초기화에 실패했습니다:

  Reviewer — surface:4 — authentication required

해결:
  1. `cmux focus-pane --pane <pane_ref>` 로 해당 pane으로 이동
  2. 직접 로그인/복구 작업 수행
  3. 복구 후 `project:reload`를 다시 실행하거나 `project:status`로 재확인
```

**Reload 시 (누락된 것만 복원):**

```
✅ 에이전트 복원 완료

  Implementer  — ✅ 기존 유지 (surface:3, session: a1b2c3d4…)
  Reviewer     — ✅ 새로 생성 + ready (surface:5, session: f9e8d7c6…)

모든 에이전트가 실행 중입니다.
```

## splitFrom Dependency Resolution

`layout.splits`는 순차 처리되며, 각 split의 `from`은 이미 `surface_map`에 존재해야 한다.

| 시나리오 | 처리 |
|----------|------|
| 에이전트 A 존재 + B 없음 (B.from=A) | B는 기존 A의 surface에 split |
| A, B 모두 없음 (B.from=A) | A를 먼저 생성 → B는 새 A의 surface에 split |
| A 없음 + B 존재 | A만 생성 (from: "claude"), B는 skip |
| A, B 모두 존재 | 모두 skip, local_workspace / local_surfaces만 갱신 |
| A가 CLI missing으로 skipped + B.from=A | B도 skip (에러 리포트) |

## Design Notes

- **선결조건 체크 우선**: PRD + 에이전트 설계 없이는 배포 불가
- **멱등성**: 여러 번 실행해도 결과 동일. 이미 있는 것은 유지, 없는 것만 생성
- **AGENTS.md 보장**: 선결조건 단계에서 프로젝트 루트 `AGENTS.md`가 없으면 플러그인에서 자동 복원한다. 페르소나 주입 시에도 preamble로 AGENTS.md 선행 참조를 지시하여 공통 규범이 개인 페르소나보다 우선 적용되도록 한다.
- **페르소나 주입 (v0.3)**: 각 신규 pane은 `agent.agent_file` (`.claude/agents/{id}.md`) 내용을 첫 메시지로 받는다. 기존 pane은 건드리지 않음 (이미 페르소나가 들어간 상태로 간주).
- **Readiness 검증 (v0.5)**: 페르소나 주입 직후와 전체 배포 마지막에 `scripts/verify-pane-ready.sh`로 각 pane의 화면을 읽어 ready 마커를 확인한다. "pane은 살아있지만 CLI가 크래시/인증 실패로 프롬프트에 도달하지 못한" 상태를 조기 감지하여 `local_surfaces.status='error'`로 기록하고 사용자에게 수동 개입을 안내한다.
- **Session resume (v0.7)**: `local_surfaces.cli_session_id`가 있는 Claude/Codex pane은 누락분 재생성 시 `claude --resume <session_id>` 또는 `codex resume <session_id>`로 시작한다. 기존 pane은 launch하지 않고 session metadata만 보존한다.
- **Session capture (v0.7)**: 신규/resume pane 모두 readiness 검증 뒤 CLI별 session 파일 휴리스틱으로 id를 다시 캡처한다. 캡처 실패는 배포 실패가 아니며 다음 reload에서 fresh launch fallback이 된다.
- **local_workspace / local_surfaces는 항상 교체**: 매 실행마다 `reset-local.sql`로 정리 후 현재 cmux 상태로 재 INSERT
- **progress.deployed 관리**: 성공 시 `true`로 세팅. `project:reset`이나 에이전트 변경 시 외부에서 `false`로 리셋됨. **`error` 상태 pane이 있어도 `deployed=1`로 세팅**한다 — 배포 자체는 완료됐고, 개별 pane 수습은 사용자 몫이기 때문.

## Edge Cases

- **모든 에이전트 이미 running**: local_surfaces만 갱신, `progress.deployed.completed = 1` 유지 (페르소나 재주입은 skip — 기존 pane의 대화를 깨지 않음)
- **일부만 running**: 누락분만 생성 + 그 pane에만 페르소나 주입
- **session_id가 있고 CLI 세션 파일도 있음**: 누락 pane은 resume 명령으로 시작하고, 이후 Step 6.10에서 최신 session id를 다시 캡처
- **session_id가 있지만 CLI 측 세션 파일이 사라짐**: warning을 출력하고 `agent.launch_command`로 fresh launch fallback. 캡처 성공 시 새 session id로 갱신
- **session capture 실패**: `cli_session_id=NULL`, `last_active_at=NULL`로 기록. `custom`은 기본적으로 이 상태가 정상
- **`agent_file`이 없거나 파일 누락**: 페르소나 주입 skip + 경고. pane은 정상 생성/실행. 사용자에게 `project:agent`로 복구 안내.
- **프로젝트 루트 `AGENTS.md` 누락 + 플러그인에도 없음**: 경고 후 배포는 계속. 사용자에게 수동 작성 또는 플러그인 재설치 권고. 공통 규범 없이 운영되는 상태이므로 caller가 hand-off 시 규범을 매번 명시해야 한다.
- **페르소나 주입 시 CLI가 아직 준비 안 됨**: Step 6.9 readiness 검증에서 최대 `--retries 10 --interval 1.5`로 폴링, Step 9b에서 한 번 더 재검증. 둘 다 실패하면 `error` 상태로 기록하고 사용자에게 수동 개입 안내 (재시도 루프를 무한대로 돌지 않음).
- **readiness 검증 자체 실패**: `verify-pane-ready.sh`가 exit 3(스크립트/cmux 오류)이면 경고만 남기고 `status='running'`으로 기록. 검증 실패가 배포 실패로 번지지 않는다.
- **ready 마커가 커스텀 CLI라 매칭 안 됨**: `type='custom'`은 shell prompt (`$`, `%`, `>`)만 검사한다. 더 정확한 검증이 필요하면 `scripts/verify-pane-ready.sh`의 패턴을 프로젝트에 맞게 확장.
- **의존 에이전트 skipped**: split 불가 리포트, 해당 에이전트도 skip
- **new-split 실패**: stderr 캡처, 사용자에게 cmux 에러 전달
- **cmux 없음**: 선결조건에서 차단
- **모든 에이전트가 CLI missing**: 모두 skipped, `progress.deployed.completed = false` 유지

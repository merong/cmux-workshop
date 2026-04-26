---
name: project-agent
description: >
  Orchestrate AI agent team composition (phase 2 of 3). Selects pre-built personas
  from the plugin's local agent library (plugins/cmux-workshop/agents/) — and when no
  suitable role exists, searches the VoltAgent awesome-claude-code-subagents repo
  via the bundled scripts/agent-list.sh + scripts/agent-fetch.sh helpers. Copies
  chosen .md files into the project's .claude/agents/, customizes them with the
  project's PRD context, and records the binding in .claude/project.db.
  Trigger on "project agent", "project:agent", "에이전트 설계", "에이전트 브레인스토밍",
  "agent design", "agent orchestrate", "에이전트 페르소나 설정", "AI 에이전트 구성",
  "에이전트 팀 구성", "compose agents", "프로젝트 에이전트 추가", "add agent",
  "에이전트 추가", "에이전트 교체", "swap agent", "에이전트 모델 변경".
  Requires PRD phase completed (project:init must run first).
  Populates agents + layout_splits tables and marks progress.agents complete.
  Auto-migrates project_info for legacy projects before any read/write.
  Does NOT touch cmux panes — use project:reload to deploy.
version: 0.6.0
---

# Project Agent — AI 에이전트 팀 오케스트레이션

프로젝트의 **2단계** 스킬. 이 스킬은 **에이전트 오케스트레이터**이다. 페르소나를 새로 작성하기보다 **미리 준비된 에이전트 라이브러리에서 역할을 선택하여 프로젝트에 주입한다.** 선택된 `.md` 파일은 프로젝트의 `.claude/agents/`로 복사되고, 각 cmux pane은 `project:reload` 시 이 파일을 페르소나로 전달받는다.

## cmux-workshop Project Workflow

| Phase | Skill | 역할 |
|-------|-------|------|
| 1 | `project:init` | PRD 작성 (brainstorming 기반) |
| **2** | **`project:agent`** ← 현재 스킬 | 에이전트 팀 오케스트레이션 |
| 3 | `project:reload` | cmux 배포 (페르소나 주입 포함) |

## Prerequisites (선결조건)

1. `.claude/project.db`가 존재 (`tools/db.sh exists`)
2. `progress.prd.completed = 1`
3. `project_info` 행이 존재 — **없으면 migration 강제**
4. cmux 환경 (`CMUX_WORKSPACE_ID` 존재, `cmux ping` 성공)
5. `gh` CLI (VoltAgent fallback이 필요할 때)

**선결조건 불충족 시:**

| 상태 | 동작 |
|------|------|
| `NO_PROJECT_DB` | "프로젝트가 초기화되지 않았습니다. `project:init`을 먼저 실행하세요." → **중단** |
| `progress.prd.completed != 1` | "PRD가 아직 완성되지 않았습니다. `project:init`을 먼저 완료하세요." → **중단** |
| `project_info` 비어 있음 | **중단하지 않음** — `project-info-capture.sh` 자동 실행하여 migration 후 계속 진행 |
| `project_info.project_root != $PWD` | 경로 변경 감지 → `project-info-capture.sh` 재실행 후 계속 진행 |
| `CMUX_WORKSPACE_ID` 없음 | "cmux 안에서 실행해야 합니다." → **중단** |
| `gh` 없음 | 경고만 하고 로컬 라이브러리만 사용 (VoltAgent 검색 skip) |

선결조건 체크 예시:

```bash
DB="${CLAUDE_PLUGIN_ROOT}/tools/db.sh"
CAPTURE="${CLAUDE_PLUGIN_ROOT}/tools/scripts/project-info-capture.sh"

"$DB" exists || { echo "NO_PROJECT_DB"; exit 1; }
"$DB" scalar "SELECT completed FROM progress WHERE phase='prd'"   # must be 1

# project_info bootstrap (migration — 모든 project-* 스킬 공통 규칙)
HAS_INFO=$("$DB" scalar "SELECT COUNT(*) FROM project_info WHERE id = 1")
if [[ "$HAS_INFO" != "1" ]]; then
    "$CAPTURE" --quiet
elif [[ "$("$DB" scalar "SELECT project_root FROM project_info WHERE id=1")" != "$PWD" ]]; then
    "$CAPTURE" --quiet
fi
```

> **공통 규칙**: 모든 project-* 스킬은 읽기/쓰기 전에 위의 `project_info`
> bootstrap을 수행한다. 기존에 DB가 있었지만 `project_info`가 없는 레거시
> 프로젝트도 자동으로 migration된다.

## Agent Sources (우선순위 순)

### 1. 로컬 라이브러리 (우선)

```
${CLAUDE_PLUGIN_ROOT}/agents/*.md
```

플러그인에 번들된 페르소나. 자주 사용되는 역할이 미리 준비되어 있다. **항상 여기서 먼저 찾는다.**

### 2. VoltAgent awesome-claude-code-subagents (fallback)

100+ 전문 subagent가 10개 카테고리로 분류된 GitHub 리포. 로컬에 없으면 여기서 fetch.

| 카테고리 | 분야 |
|----------|------|
| `01-core-development` | backend/frontend/fullstack/api-designer/microservices-architect |
| `02-language-specialists` | python/typescript/rust/go/java/kotlin 등 |
| `03-infrastructure` | devops/kubernetes/terraform/cloud |
| `04-quality-security` | security-auditor/penetration-tester/code-reviewer |
| `05-data-ai` | ml-engineer/data-scientist/llm-engineer |
| `06-developer-experience` | documentation-engineer/dx-optimizer |
| `07-specialized-domains` | blockchain/game-dev/embedded |
| `08-business-product` | product-manager/business-analyst |
| `09-meta-orchestration` | task-distributor/workflow-orchestrator |
| `10-research-analysis` | research-analyst/trend-analyst |

### 3. 신규 작성 (최후 수단)

로컬/VoltAgent 어디에도 없으면 사용자와 협업하여 직접 작성.

## Helper Scripts (inline gh api 금지)

**이 스킬은 `gh api`를 직접 호출하지 않는다.** 반드시 아래 스크립트를 사용:

### `scripts/agent-list.sh` — 후보 검색

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/project-agent/scripts/agent-list.sh" \
  [--source local|voltagent|all] \
  [--category CATEGORY] \
  [--keyword KEYWORD] \
  [--json]
```

출력 예시 (기본):
```
[local] orchestrator           Lead coordinator and task distributor...
[local] implementer             Fast, pragmatic coder...
[volt]  backend-developer       (category: 01-core-development)
[volt]  fullstack-developer     (category: 01-core-development)
```

`--json` 사용 시 프로그램적 파싱 가능.

### `scripts/agent-fetch.sh` — 단일 에이전트 복사/다운로드

```bash
# 로컬 복사
bash "${CLAUDE_PLUGIN_ROOT}/skills/project-agent/scripts/agent-fetch.sh" \
  --source local --name implementer --dest .claude/agents/implementer.md

# VoltAgent 다운로드
bash "${CLAUDE_PLUGIN_ROOT}/skills/project-agent/scripts/agent-fetch.sh" \
  --source voltagent --category 04-quality-security --name code-reviewer \
  --dest .claude/agents/reviewer.md
```

성공 시 stdout에 `OK <source> <origin> -> <dest>` 출력. 실패 시 비-0 exit + stderr 에러.

## AI Models → cmux CLI 매핑

| Type | CLI binary | launch_command | Default model | 적합 |
|------|-----------|----------------|---------------|------|
| `claude` | `claude` | `claude --dangerously-skip-permissions` | Claude Opus 4.6 | 오케스트레이션, 깊은 분석, 디버그, 리서치 |
| `codex` | `codex` | `codex --full-auto` | GPT-5.x | 빠른 구현, 디자인/아키텍처, 프론트엔드, 리뷰 |
| `custom` | (지정) | (지정) | (지정) | 특수 목적 |

에이전트 `.md` frontmatter의 `model` 필드(`opus`/`sonnet`/`haiku`)는 **성격의 힌트**이지 엄격한 제약이 아니다. cmux type은 페르소나와 역할을 보고 사용자가 결정한다.

## Persona → CLI 기본 매핑

| Persona / 역할 | 기본 CLI | 이유 |
|---|---|---|
| `orchestrator` | `claude` | 전체 맥락 유지와 위임 조율 |
| `implementer` | `codex` | 빠른 구현과 코드 변경 |
| `reviewer` | `codex` | 코드 리뷰, 대안 제시, diff 분석 |
| `architect` / `design` / `frontend` | `codex` | 설계 검토, UI/프론트엔드 구현과 리뷰 |
| `debugger` | `claude` | 원인 분석과 장기 컨텍스트 추적 |
| `researcher` | `claude` | 문서 조사와 근거 정리 |

사용 가능한 기본 CLI는 `claude`와 `codex`뿐이다. 과거 지원 중단 CLI로 저장된 row는 migration 004에서 `codex`로 보존 변환된다.

## Workflow

### Step 1: Check prerequisites

선결조건 검증. 실패 시 즉시 중단.

### Step 2: Read PRD and existing config

```bash
DB="${CLAUDE_PLUGIN_ROOT}/tools/db.sh"

cat .claude/PRD.md

# Project meta
"$DB" json "$(cat "${CLAUDE_PLUGIN_ROOT}/tools/queries/get-project.sql")"

# Already-configured agents (may be empty)
"$DB" json "$(cat "${CLAUDE_PLUGIN_ROOT}/tools/queries/get-agents.sql")"

ls -la .claude/agents/ 2>/dev/null
```

`SELECT COUNT(*) FROM agents`가 0보다 크면 이미 설계된 상태. modification mode
진입 여부를 사용자에게 묻는다 (추가/교체/제거/전체 재구성).

### Step 3: Brainstorm roles (역할 먼저)

PRD의 목표/작업/복잡도에서 **역할 조합**을 도출. AI 모델이나 CLI 선택은 아직 하지 않는다.

| 프로젝트 유형 | 추천 역할 조합 |
|---------------|----------------|
| 웹 풀스택 | orchestrator + implementer + reviewer |
| API/백엔드 | orchestrator + backend-developer + security-auditor |
| 데이터/ML | orchestrator + ml-engineer + researcher |
| 라이브러리/SDK | orchestrator + implementer + architect |
| 대규모 | orchestrator + architect + implementer + reviewer |

사용자에게 제안 후 승인 대기:

```
PRD 분석:
  - 유형: {type}
  - 핵심 작업: {top 3~5}

추천 역할:
  1. orchestrator  (Claude caller)
  2. implementer   (구현)
  3. reviewer      (리뷰)

이 조합으로 진행할까요? 추가/변경 요청 가능.
```

### Step 4: Resolve each role to an agent .md

각 역할마다 순서대로:

#### 4a. 로컬 검색

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/project-agent/scripts/agent-list.sh" \
  --source local --keyword "{role}"
```

결과가 있으면 사용자에게 보여주고 "이것으로 사용?" 확인.

#### 4b. VoltAgent 검색 (로컬에 없거나 사용자가 원할 때)

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/project-agent/scripts/agent-list.sh" \
  --source voltagent --keyword "{role}"
```

후보 `.md` 목록에서 사용자가 하나 선택. 이름과 카테고리를 기록.

#### 4c. 신규 작성

어디에도 없거나 사용자가 거부하면 PRD를 참고하여 직접 작성. 프론트매터(`name`, `description`, `model`) + 본문(역할, 작업 스타일, 출력 포맷) 구조를 따른다.

### Step 5: Fetch/copy into project

확정된 각 에이전트를 `.claude/agents/{agent-id}.md`로 복사:

```bash
# 로컬 예시
bash "${CLAUDE_PLUGIN_ROOT}/skills/project-agent/scripts/agent-fetch.sh" \
  --source local --name implementer \
  --dest .claude/agents/implementer.md

# VoltAgent 예시
bash "${CLAUDE_PLUGIN_ROOT}/skills/project-agent/scripts/agent-fetch.sh" \
  --source voltagent --category 04-quality-security --name code-reviewer \
  --dest .claude/agents/reviewer.md
```

스크립트가 비-0로 끝나면 stderr를 사용자에게 전달하고 해당 에이전트는 skip.

### Step 5.5: Sync AGENTS.md to project root (AGENTS.md 전파)

프로젝트 루트에 **`AGENTS.md`가 없으면 플러그인의 표준 사본을 복사**한다. 이 파일은 모든 에이전트의 공통 동작 규범(업무 수신/보고 형식, 파괴적 작업 규칙, 에스컬레이션 기준)을 정의하며, 각 CLI(Codex/Claude)가 프로젝트 루트에서 자동 로드한다.

```bash
PLUGIN_AGENTS_MD="${CLAUDE_PLUGIN_ROOT}/../../AGENTS.md"   # marketplace root
# fallback: 플러그인 디렉터리 구조 변경을 대비해 한 단계 위도 탐색
[[ -f "$PLUGIN_AGENTS_MD" ]] || PLUGIN_AGENTS_MD="${CLAUDE_PLUGIN_ROOT}/AGENTS.md"

if [[ ! -f "$PLUGIN_AGENTS_MD" ]]; then
  echo "⚠️ 플러그인에서 AGENTS.md를 찾을 수 없습니다. 공통 규범 주입을 skip합니다." >&2
elif [[ ! -f "./AGENTS.md" ]]; then
  cp "$PLUGIN_AGENTS_MD" ./AGENTS.md
  echo "→ AGENTS.md를 프로젝트 루트로 복사했습니다 (에이전트 공통 규범)."
else
  # 이미 있음 → 차이 요약만 출력, 덮어쓰지 않음 (프로젝트별 커스터마이즈 보존)
  if ! cmp -s "$PLUGIN_AGENTS_MD" ./AGENTS.md; then
    echo "ℹ️  AGENTS.md가 이미 존재합니다 (플러그인 최신본과 다름). 덮어쓰지 않음."
    echo "    최신본으로 재동기화하려면 파일을 삭제 후 이 스킬을 재실행하세요."
  fi
fi
```

**규칙:**
- 이미 있는 `AGENTS.md`는 **덮어쓰지 않는다** (프로젝트가 규범을 커스터마이즈했을 수 있다).
- 플러그인에 AGENTS.md가 없는 경우(드문 배포 상태)만 skip + 경고.
- 사용자가 "최신 규범으로 재동기화"를 요청하면 `rm ./AGENTS.md` 후 이 스킬 재실행 안내.

### Step 6: Customize each copy for the project

복사된 `.claude/agents/{id}.md` 각 파일의 **본문 말미에 Project Context 블록을 append**한다. 기존 내용(frontmatter + body)은 절대 수정하지 않는다.

```markdown

---

## Project Context (Injected by project:agent)

**Project**: {project name}
**PRD**: `.claude/PRD.md`
**Operating rules**: `AGENTS.md` (프로젝트 루트) — 업무 수신/보고 표준 형식, 파괴적 작업 규칙, 에스컬레이션 기준. 이 페르소나보다 **상위**로 적용됨.
**Your role in this team**: {project-specific role phrasing}

**Project-specific guidelines**:
- {PRD에서 도출한 1~3개 구체적 지침}

**Collaborators**:
- {다른 팀원 에이전트 id — role 한 줄}

> 첫 응답 전에 `AGENTS.md`를 읽고 표준 Hand-off/Report 형식을 따를 것.
> caller(orchestrator) 이외의 pane과 직접 통신하지 말고, 불확실한 hand-off는
> 바로 착수하지 말고 caller에게 되묻는다.
```

사용자에게 주입될 내용을 보여주고 승인받은 뒤 Edit 도구로 append.

### Step 7: Map each agent to cmux type and launch_command

`.md`의 frontmatter `model` + 역할 성격을 보고 type을 선택. 사용자에게 확인:

```
에이전트 → cmux CLI 매핑:
  orchestrator  → claude (caller, 실행 없음)
  implementer   → codex   (codex --full-auto)
  reviewer      → codex   (codex --full-auto)

이 매핑으로 진행?
```

### Step 8: Write agents + layout_splits to project.db

전체 재구성이든 첫 설계든 **같은 로직**: 기존 `agents`/`layout_splits`를
삭제하고 새로 INSERT. FK ON CASCADE로 `layout_splits`는 `agents` 삭제 시
자동 제거되지만, 순서상 layout을 먼저 지운다.

```bash
DB="${CLAUDE_PLUGIN_ROOT}/tools/db.sh"

# 1. Wipe existing agent rows (layout_splits cascades via FK)
"$DB" exec "DELETE FROM layout_splits; DELETE FROM agents;"

# 2. Insert each agent (use db.sh quote for every string literal)
AID=$("$DB" quote "claude")
ANAME=$("$DB" quote "Claude")
AROLE=$("$DB" quote "orchestrator")
AMODEL=$("$DB" quote "Claude Opus 4.6")
AFILE=$("$DB" quote ".claude/agents/orchestrator.md")
AORIGIN=$("$DB" quote "plugins/cmux-workshop/agents/orchestrator.md")

"$DB" exec "INSERT INTO agents
    (id, name, type, role, model, agent_file,
     source_type, source_origin, launch_command, cli_binary, is_caller, position)
  VALUES ($AID, $ANAME, 'claude', $AROLE, $AMODEL, $AFILE,
          'local-library', $AORIGIN, NULL, 'claude', 1, 0)"

# ... repeat for implementer, reviewer, etc. ...

# 3. Insert layout splits in execution order
"$DB" exec "INSERT INTO layout_splits (position, agent_id, direction, from_agent_id) VALUES
    (0, 'implementer', 'right', 'claude'),
    (1, 'reviewer',    'down',  'implementer')"

# 4. Mark agents phase complete
"$DB" exec "UPDATE progress
            SET completed = 1, completed_at = datetime('now')
            WHERE phase = 'agents'"

# 5. Bump project.updated_at
"$DB" exec "UPDATE project SET updated_at = datetime('now') WHERE id = 1"
```

**중요: `progress.deployed`는 건드리지 않는다** (false 유지 — 아직 cmux 배포 전).
단, modification mode에서 이미 배포된 상태를 수정할 때는 `progress.deployed`를
false로 **리셋**한다 (아래 Modification Mode 참조).

**스키마 변경 포인트 (v0.3 JSON → v0.4 SQLite):**

| 기존 JSON 필드 | SQLite 매핑 |
|----------------|-------------|
| `agents[].id / name / type / role / model` | `agents` 컬럼 동명 |
| `agents[].agent_file` | `agents.agent_file` |
| `agents[].source.type` | `agents.source_type` |
| `agents[].source.origin` | `agents.source_origin` |
| `agents[].is_caller` (boolean) | `agents.is_caller` (0/1) |
| `layout.splits[].from` | `layout_splits.from_agent_id` |
| `layout.splits[]` 순서 | `layout_splits.position` (0..N) |
| `progress.agents.completed` | `progress` row where phase='agents' |

쿼리 템플릿 참조: `skills/project-agent/scripts/queries/`.

### Step 9: Report and guide to next step

```
✅ 에이전트 팀 오케스트레이션 완료

┌──────────────┬──────────────────┬──────────────┬──────────────────────────┐
│ Agent        │ Role             │ Type         │ Source                   │
├──────────────┼──────────────────┼──────────────┼──────────────────────────┤
│ Claude       │ orchestrator     │ caller       │ local: orchestrator      │
│ Implementer  │ 코드 구현          │ codex        │ local: implementer       │
│ Reviewer     │ 코드 리뷰/대안     │ codex        │ voltagent: 04-.../code-reviewer │
└──────────────┴──────────────────┴──────────────┴──────────────────────────┘

프로젝트 파일:
  .claude/agents/orchestrator.md    (복사됨 + Project Context 주입)
  .claude/agents/implementer.md     (복사됨 + Project Context 주입)
  .claude/agents/reviewer.md        (복사됨 + Project Context 주입)

진행 단계:
  [✅] 1. PRD 작성
  [✅] 2. 에이전트 설계
  [  ] 3. cmux 배포             ← 다음 단계

👉 다음 단계: `project:reload`로 cmux에 배포하세요.
   배포 시 각 pane에 `.claude/agents/{id}.md` 내용이 페르소나로 주입됩니다.
```

## Modification Mode

기존 `progress.agents.completed = 1` 프로젝트에서:

### 에이전트 추가 (append)

```bash
# 새 row 하나 INSERT (position은 기존 MAX+1)
"$DB" exec "INSERT INTO agents (id, name, type, role, model, agent_file,
                                source_type, source_origin, launch_command, cli_binary,
                                is_caller, position)
  VALUES (...)"

# layout_splits에도 분할 하나 append
"$DB" exec "INSERT INTO layout_splits (position, agent_id, direction, from_agent_id)
  VALUES ((SELECT COALESCE(MAX(position), -1) + 1 FROM layout_splits),
          '<new-id>', '<direction>', '<from>')"

# 이미 배포된 경우 deployed 리셋
"$DB" exec "UPDATE progress SET completed = 0, completed_at = NULL WHERE phase = 'deployed'"
```

### 에이전트 교체 (swap)
1. 교체할 `agent_id` 선택
2. 새 소스 선택 (`agent-list.sh`) + fetch (`agent-fetch.sh --dest .claude/agents/{id}.md` — 덮어쓰기)
3. 덮어쓰기 전에 사용자 확인 + Project Context 블록 재적용
4. `UPDATE agents SET name=..., model=..., source_origin=..., launch_command=... WHERE id=<id>`
5. `name`/`launch_command`가 바뀌면 deployed 리셋
6. `agent_file` 경로 자체는 동일하게 유지 (id가 같으면)

### 에이전트 제거
1. `DELETE FROM agents WHERE id='<id>'` (layout_splits는 FK CASCADE)
2. `layout_splits.from_agent_id`가 제거된 id를 참조하던 다른 행은 수동 교정
3. `.claude/agents/{id}.md` 삭제 여부를 사용자에게 확인 (기본: 보존)
4. deployed 리셋

### 커스터마이즈만 수정
`.claude/agents/{id}.md` 파일의 Project Context 블록만 다시 작성. DB는 수정하지
않는다. `progress.deployed`는 유지되나 pane에 재주입하려면 `project:reload`
필요.

## Design Notes

- **오케스트레이터 역할**: 이 스킬은 페르소나를 **작성**하지 않고 **선택·조합·커스터마이즈**한다.
- **로컬 우선**: 매번 새로 쓰지 말고 재사용. 프로젝트 특수성은 Project Context 주입 블록으로 해결.
- **AGENTS.md 전파**: 모든 에이전트가 공유할 **공통 규범**은 페르소나 파일이 아니라 프로젝트 루트 `AGENTS.md`에 둔다. 페르소나는 역할별 개성만 담고, 업무 수신/보고 표준·파괴적 작업 규칙·에스컬레이션은 AGENTS.md가 단일 소스다. Step 5.5가 이 파일을 보장한다.
- **스크립트 추상화**: `gh api` 직접 호출을 SKILL 본문에 넣지 않는다. 모든 외부 조회는 `scripts/agent-list.sh`와 `scripts/agent-fetch.sh`를 통과한다. 이를 통해 향후 소스 추가(예: Anthropic 공식 subagent 저장소)가 단일 지점에서 가능.
- **출처 추적**: `source` 필드로 기원을 명시 → 원본 업데이트 감지, 재동기화 가능.
- **cmux 독립 (파일 쓰기)**: 이 스킬은 `.md` 복사와 `project.db` 업데이트만 한다. cmux pane 생성과 페르소나 주입은 `project:reload`의 책임.

## Edge Cases

- **로컬 라이브러리가 비어있음**: `agent-list.sh --source local`이 빈 결과. VoltAgent 강제. `gh` 없으면 수동 작성.
- **VoltAgent fetch 실패** (오프라인, rate limit, gh 미인증): `agent-fetch.sh`가 비-0. stderr를 사용자에게 보여주고 다른 후보 시도 또는 수동 작성.
- **사용자가 모든 제안 거부**: 수동 작성 모드. PRD를 참조하여 템플릿 제공.
- **동일 `agent_id` 충돌**: id rename 요구.
- **`.claude/agents/` 이미 존재 + project.db와 불일치**: 사용자에게 상태 보여주고 정리 방식(무시/삭제/재사용) 선택받는다.
- **VoltAgent `.md`의 frontmatter가 표준과 다름**: 그대로 복사, Project Context 블록만 append.
- **프로젝트 루트에 기존 `AGENTS.md`가 있음**: 덮어쓰지 않는다. 사용자가 재동기화를 원하면 수동 삭제 후 재실행을 안내 (Step 5.5).
- **플러그인에 AGENTS.md가 없음**: 경고 출력 + skip. 다른 작업은 정상 진행. 사용자에게 플러그인 재설치 권고.

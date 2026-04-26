---
name: project-reset
description: >
  Reset project workspace at any phase — close cmux panes, remove PRD, and clear project.db tables.
  Trigger on "project reset", "project:reset", "프로젝트 리셋", "프로젝트 초기화 해제",
  "project clean", "프로젝트 클린", "reset workspace", "워크스페이스 리셋",
  "에이전트 정리", "clear project", "프로젝트 정리", "remove project agents",
  "에이전트 제거", "project destroy", "프로젝트 삭제", "teardown project",
  "프로젝트 롤백", "phase 되돌리기".
  Supports full reset (delete db + files + panes) or partial reset (panes only, agents only, PRD only).
  Auto-migrates project.db schema/project_info for legacy projects before partial resets (full reset skips migration since it deletes everything anyway).
version: 0.4.1
---

# Project Reset

프로젝트를 리셋한다. cmux pane 닫기, `.claude/project.db` 삭제 또는 테이블 정리, `.claude/PRD.md` / `.claude/agents/` 삭제, 특정 phase만 되돌리기를 모두 지원한다.

## cmux-workshop Project Workflow

이 스킬은 프로젝트 상태를 어느 단계로든 되돌릴 수 있다:

| Phase | Skill |
|-------|-------|
| 1 | `project:init` — PRD 작성 |
| 2 | `project:agent` — 에이전트 설계 |
| 3 | `project:reload` — cmux 배포 |
| - | **`project:reset`** ← 현재 스킬 — 리셋 |

## Prerequisites (선결조건)

- 없음 (어떤 상태에서든 실행 가능)
- cmux 외부에서도 실행 가능 (pane 닫기만 skip, 파일 삭제는 수행)
- **부분 리셋 모드(2~5)**에서는 DB를 유지하므로, `project_info`가 비어 있으면
  먼저 `project-info-capture.sh`로 migration한 뒤 리셋을 적용한다 (공통 규칙).
  **전체 리셋(모드 1)**은 DB 파일 자체를 삭제하므로 migration을 건너뛴다.

```bash
DB="${CLAUDE_PLUGIN_ROOT}/tools/db.sh"
CAPTURE="${CLAUDE_PLUGIN_ROOT}/tools/scripts/project-info-capture.sh"

# 모드 1(전체 리셋)이 아닌 경우에만 수행
if [[ "$MODE" != "1" ]] && "$DB" exists; then
    "$DB" migrate
    HAS_INFO=$("$DB" scalar "SELECT COUNT(*) FROM project_info WHERE id = 1")
    [[ "$HAS_INFO" != "1" ]] && "$CAPTURE" --quiet
fi
```

## Reset Modes

사용자 요청에 따라 다른 수준의 리셋을 수행한다:

| 모드 | 트리거 표현 | 동작 |
|------|------------|------|
| **전체 리셋** | "project reset", "프로젝트 리셋", "프로젝트 삭제" | pane 닫기 + PRD 삭제 + `.claude/agents/` 삭제 + project.db 삭제. 저장된 CLI session metadata도 사라져 다음 reload는 fresh 시작 |
| **배포만 해제** | "에이전트만 닫아줘", "배포 취소", "pane만 정리" | pane 닫기 + local_workspace/local_surfaces 비움(session 컬럼 포함) + `progress.deployed.completed = 0` (나머지 유지) |
| **에이전트 재설계** | "에이전트 설계 되돌려", "에이전트 리셋" | pane 닫기 + agents/layout_splits 비움 + local 비움 + `progress.agents/deployed = 0` (PRD 유지) |
| **PRD만 삭제** | "PRD 삭제", "PRD만 지워" | PRD 파일 삭제 + `prd` 테이블 비움 + `progress.prd.completed = 0` (에이전트/배포 상태는 유지) |
| **파일만 삭제** | "설정만 삭제해줘", "파일만 지워" | project.db + PRD 삭제 (pane 유지) |

사용자의 요청이 모호하면 모드를 확인한다:

```
어떤 수준으로 리셋할까요?
  1. 전체 리셋 — 모든 것 삭제, Phase 0으로
  2. cmux 배포만 해제 — pane 닫기, 설계는 유지
  3. 에이전트 재설계 — pane 닫기 + 에이전트 구성 리셋, PRD 유지
  4. PRD만 삭제 — PRD 파일 제거
  5. 파일만 삭제 — pane 유지, 설정 파일만 제거
```

## Resources

- [cmux CLI Reference](../project-init/references/cmux-cli-reference.md)

## Workflow

### Step 1: Verify cmux environment (optional)

```bash
if [ -z "${CMUX_WORKSPACE_ID:-}" ]; then echo "NOT_IN_CMUX"; else cmux ping && echo "CMUX_OK"; fi
```

`NOT_IN_CMUX`여도 파일 작업은 진행. pane 닫기만 skip.

### Step 2: Read project.db state

```bash
DB="${CLAUDE_PLUGIN_ROOT}/tools/db.sh"
"$DB" exists || echo "NO_PROJECT_DB"
```

**`NO_PROJECT_DB`인 경우:**
- PRD 파일 (`.claude/PRD.md`) 또는 `.claude/agents/` 디렉토리만 남아 있을 수도 있음 → 삭제 옵션 제시
- 그 외에는 "이미 초기화되지 않은 상태입니다." 안내 후 중단

DB가 있으면 아래 쿼리로 상태 파악:

```bash
"$DB" json "$(cat "${CLAUDE_PLUGIN_ROOT}/tools/queries/get-agents.sql")"
"$DB" json "$(cat "${CLAUDE_PLUGIN_ROOT}/tools/queries/get-layout.sql")"
"$DB" json "$(cat "${CLAUDE_PLUGIN_ROOT}/tools/queries/get-progress.sql")"
"$DB" scalar "SELECT path FROM prd WHERE id=1"
"$DB" json "$(cat "${CLAUDE_PLUGIN_ROOT}/tools/queries/get-surfaces.sql")"
```

### Step 3: Show current state

현재 상태와 리셋 대상을 표시:

```
프로젝트 현재 상태:
  [✅] 1. PRD 작성 완료        (.claude/PRD.md)
  [✅] 2. 에이전트 설계 완료    (3개 에이전트)
  [✅] 3. cmux 배포 완료        (surface:3, surface:4)

선택한 모드: {mode}

영향:
  - 닫을 pane: Implementer (surface:3), Reviewer (surface:4)
  - 삭제할 파일: .claude/project.db, .claude/PRD.md, .claude/agents/

⚠️ 이 작업은 되돌릴 수 없습니다. 진행할까요?
```

사용자가 거부하면 중단.

### Step 4: Close agent panes (mode에 따라)

**pane을 닫는 모드** (전체 리셋 / 배포만 해제 / 에이전트 재설계):

cmux 환경 내부인 경우에만 실행.

```bash
cmux tree --json
```

`layout_splits` 역순으로 non-caller 에이전트의 `name`과 일치하는 surface를 찾아 닫는다:

```bash
cmux close-surface --surface <surface_ref>
```

예시 (Implementer가 먼저 생성 → Reviewer가 나중 생성):
```bash
# Reviewer 먼저 (나중에 생성됨)
cmux close-surface --surface surface:4
# 그 다음 Implementer
cmux close-surface --surface surface:3
```

title이 트리에서 발견되지 않으면 skip (이미 닫혀 있음).

**caller pane은 절대 닫지 않음** (`is_caller = 1`).

### Step 5: Apply mode-specific changes

#### 모드 1: 전체 리셋

```bash
rm -f .claude/project.db
rm -f .claude/PRD.md
rm -rf .claude/agents   # 비어 있으면 무시되고, 복사본이 있으면 제거
```

`.claude/` 디렉토리 자체는 **유지** (다른 Claude Code 설정 보존).

#### 모드 2: cmux 배포만 해제

- pane 닫기 (Step 4에서 이미 실행)
- local 테이블 비움:

  ```bash
  "$DB" run "${CLAUDE_PLUGIN_ROOT}/tools/queries/reset-local.sql"
  ```

- deployed progress 리셋:

  ```bash
  "$DB" exec "UPDATE progress SET completed=0, completed_at=NULL WHERE phase='deployed'"
  "$DB" exec "UPDATE project SET updated_at=datetime('now') WHERE id=1"
  ```

- `project.db`의 나머지 데이터와 PRD는 유지.
- `local_surfaces`를 DELETE하므로 `cli_session_id`/`cli_session_label`/`last_active_at`도 함께 삭제된다. 다음 `project:reload`는 저장된 session이 없어 fresh launch한다.

#### 모드 3: 에이전트 재설계

- pane 닫기 (Step 4에서 이미 실행)
- 에이전트/레이아웃/로컬 정리:

  ```bash
  "$DB" exec "DELETE FROM layout_splits; DELETE FROM agents;"
  "$DB" run "${CLAUDE_PLUGIN_ROOT}/tools/queries/reset-local.sql"
  "$DB" exec "UPDATE progress SET completed=0, completed_at=NULL WHERE phase IN ('agents','deployed')"
  "$DB" exec "UPDATE project SET updated_at=datetime('now') WHERE id=1"
  ```

- `.claude/agents/` 내부 `.md` 파일 삭제 여부 사용자 확인 (기본: 보존 — 다음 `project:agent`에서 덮어쓰기 가능).
- PRD와 `progress.prd`는 유지.

#### 모드 4: PRD만 삭제

- `.claude/PRD.md` 삭제
- DB 갱신:

  ```bash
  "$DB" exec "DELETE FROM prd"
  "$DB" exec "UPDATE progress SET completed=0, completed_at=NULL WHERE phase='prd'"
  "$DB" exec "UPDATE project SET updated_at=datetime('now') WHERE id=1"
  ```

- 에이전트/배포 상태는 유지 (사용자 확인 하에)
- ⚠️ 경고: "PRD를 삭제해도 기존 에이전트 설계는 유지됩니다. 설계도 초기화하려면 모드 3을 사용하세요."

#### 모드 5: 파일만 삭제

```bash
rm -f .claude/project.db
rm -f .claude/PRD.md
rm -rf .claude/agents
```

cmux pane은 유지. 이 경우 남은 pane은 orphan 상태가 됨 (수동으로 닫거나 무시).

### Step 6: Return focus to Claude pane

cmux 내부인 경우:

```bash
cmux focus-pane --pane <caller_pane_ref>
```

### Step 7: Notify and report

```bash
cmux notify --title "Project Reset" --body "{mode 요약}"
```

**모드별 리포트:**

#### 전체 리셋

```
✅ 프로젝트 전체 리셋 완료

삭제:
  - Implementer pane (surface:3) 닫힘
  - Reviewer pane (surface:4) 닫힘
  - .claude/PRD.md 삭제
  - .claude/project.db 삭제
  - .claude/agents/ 삭제

진행 단계:
  [  ] 1. PRD 작성          ← 여기부터 다시 시작
  [  ] 2. 에이전트 설계
  [  ] 3. cmux 배포

새 프로젝트를 시작하려면 `project:init`을 사용하세요.
```

#### cmux 배포만 해제

```
✅ cmux 배포 해제 완료

닫힌 pane:
  - Implementer, Reviewer

유지된 항목:
  - .claude/PRD.md
  - .claude/project.db (에이전트 설계 보존)

진행 단계:
  [✅] 1. PRD 작성
  [✅] 2. 에이전트 설계
  [  ] 3. cmux 배포          ← 여기부터 재실행

재배포: `project:reload`
```

#### 에이전트 재설계

```
✅ 에이전트 설계 리셋 완료

진행 단계:
  [✅] 1. PRD 작성
  [  ] 2. 에이전트 설계      ← 여기부터 다시 시작
  [  ] 3. cmux 배포

에이전트 재설계: `project:agent`
```

#### PRD만 삭제

```
✅ PRD 삭제 완료

삭제: .claude/PRD.md

진행 단계:
  [  ] 1. PRD 작성          ← 여기부터 다시 시작
  [✅] 2. 에이전트 설계 (기존 설계 보존)
  [✅] 3. cmux 배포

PRD 재작성: `project:init`
```

## Design Notes

- **모드 선택 가능**: 사용자가 원하는 수준의 리셋을 제공
- **pane 역순 닫기**: `layout.splits` 역순으로 닫아 레이아웃 안정성 유지
- **caller pane 절대 보호**: `is_caller = 1`인 에이전트는 항상 skip
- **.claude 디렉토리 보존**: 다른 Claude Code 설정 파괴 방지
- **Session preservation**: local reset/full reset은 session metadata를 보존하지 않는다. 세션을 이어가려면 pane을 유지한 상태에서 `project:reload`로 EXISTING 감지만 수행한다.

## Edge Cases

- **project.db 없음**: 모드 4 (PRD만 삭제)만 의미 있음. 다른 모드는 중단 안내
- **PRD 파일 없음 (DB에는 있다고 기록됨)**: 경고만 표시, DB 업데이트는 수행
- **cmux 미실행**: pane 닫기 skip, 파일 작업만 수행
- **일부 pane 이미 닫힘**: tree에서 발견되지 않으면 skip
- **caller pane 실수로 닫기 방지**: `is_caller: true`인 에이전트는 절대 닫지 않음
- **partial reset 후 상태 혼선**: progress 필드로 일관성 보장

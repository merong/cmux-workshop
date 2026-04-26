---
name: project-init
description: >
  Initialize a new project by running mandatory brainstorming (via superpowers:brainstorming)
  and converting the approved design into a PRD (Product Requirements Document).
  Trigger on "project init", "project:init", "프로젝트 초기화", "프로젝트 시작",
  "project setup", "프로젝트 셋업", "프로젝트 PRD", "PRD 작성", "프로젝트 요구사항 정리",
  "init project", "워크스페이스 초기화", "프로젝트 kick-off", "프로젝트 기획",
  "프로젝트 브레인스토밍", "project brainstorm".
  Requires cmux environment. MUST delegate ideation to superpowers:brainstorming
  skill, then writes .claude/PRD.md and initializes .claude/project.db (phase 1 of 3).
  As the very first step (before any PRD work), installs
  .claude/script/project-view.sh — a thin shell wrapper that lets the project
  launch the cmux monitor stack from a plain terminal — and asks the user
  once whether to build, boot, and open the project-view web dashboard now.
  Then bootstraps project.db + project_info (auto-migrates existing projects)
  before PRD writing begins. Does NOT configure agents or cmux panes — use
  project:agent and project:reload for those.
version: 0.8.0
---

# Project Init — PRD 작성

프로젝트의 **1단계** 스킬. **Superpowers 플러그인의 `brainstorming` 스킬을 의무적으로 호출하여** 프로젝트 기획을 브레인스토밍으로 진행하고, 승인된 설계를 PRD(Product Requirements Document)로 변환한다. 에이전트 구성과 cmux 배포는 이 스킬의 범위가 아니다.

## 필수 의존 스킬 — Superpowers Brainstorming

이 스킬은 **단독으로 아이디어를 묻지 않는다.** 아래 스킬을 반드시 호출해야 하며, 이 과정을 건너뛰면 스킬이 실패한 것으로 간주된다:

```
Skill: superpowers:brainstorming
```

`brainstorming` 스킬은 대화형 체크리스트(프로젝트 탐색 → 질문 → 2~3가지 접근 제시 → 설계 발표 → 사용자 승인)를 실행한다. 이 스킬의 역할은 **브레인스토밍의 terminal state를 PRD 작성으로 리디렉션**하는 것이다:

| `brainstorming` 단계 | 기본 동작 | 이 스킬에서의 오버라이드 |
|----------------------|-----------|--------------------------|
| 1~5. 탐색 / 질의 / 설계 승인 | 그대로 실행 | 변경 없음 |
| 6. Write design doc | `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md` | **`.claude/PRD.md`로 대체 기록** (아래 PRD 구조 사용) |
| 7. Spec self-review | 그대로 실행 | 변경 없음 |
| 8. User reviews written spec | 그대로 실행 | 변경 없음 |
| 9. Transition to implementation | `writing-plans` 호출 | **`project:agent` 안내로 대체** (writing-plans 호출 금지) |

`brainstorming` 스킬이 제공하는 HARD-GATE("사용자 승인 없이 구현 금지")는 그대로 유지된다. 설계 승인 전에는 PRD 파일을 쓰지 않는다.

## cmux-workshop Project Workflow

이 스킬은 3단계 프로젝트 셋업 워크플로우의 **첫 번째** 단계이다:

| Phase | Skill | 역할 |
|-------|-------|------|
| **1** | **`project:init`** ← 현재 스킬 | PRD 작성 |
| 2 | `project:agent` | AI 에이전트 팀 설계 |
| 3 | `project:reload` | cmux 워크스페이스에 에이전트 배포 |

상태 확인: `project:status` / 전체 초기화: `project:reset`

## Prerequisites (선결조건)

**반드시 만족해야 할 조건:**

1. cmux가 실행 중이고 현재 터미널이 cmux 내부여야 한다 (`CMUX_WORKSPACE_ID` 환경변수 존재)
2. `cmux ping` 응답 정상
3. `superpowers:brainstorming` 스킬이 설치/활성화되어 있어야 한다 (브레인스토밍 강제 의존성)
4. **`.claude/project.db`가 존재하고 `project_info` 행이 채워져 있어야 한다** — 없으면 Step 2에서 **자동 migration**된다 (기존 프로젝트도 동일한 경로로 초기화됨)

**선결조건 불충족 시 동작 — 스킬 즉시 종료:**

| 상태 | 동작 |
|------|------|
| `CMUX_WORKSPACE_ID` 없음 | "cmux workspace 안에서 실행해야 합니다. cmux를 먼저 실행하고 그 터미널에서 다시 호출하세요." → **중단** |
| `cmux ping` 실패 | "cmux가 응답하지 않습니다. cmux 데몬을 확인하세요." → **중단** |
| `superpowers:brainstorming` 미설치 | "Superpowers 플러그인이 필요합니다. `/plugin install superpowers@claude-plugins-official`로 설치하세요." → **중단** |
| `project.db` 없음 / `project_info` 비어 있음 | **중단하지 않음** — Step 2에서 스키마 생성 + `project-info-capture.sh` 자동 실행으로 migration 후 진행 |

이 스킬은 PRD 작성 자체는 cmux를 직접 사용하지 않지만, 이어질 `project:agent` → `project:reload` 파이프라인이 cmux 내부에서만 완결되므로 **진입 시점부터** 환경을 강제한다.

## Outputs

- `.claude/project.db` — 프로젝트 메타데이터 + 진행 상태가 담긴 SQLite DB (Git 추적 가능)
- `.claude/PRD.md` — Product Requirements Document

## Data store: `.claude/project.db`

모든 프로젝트 메타데이터는 **SQLite 단일 파일** `.claude/project.db`에 저장된다.
스키마 DDL은 `${CLAUDE_PLUGIN_ROOT}/tools/schema.sql`, 사용 래퍼는
`${CLAUDE_PLUGIN_ROOT}/tools/db.sh`, 테이블 설명은 `tools/SCHEMA.md` 참조.

이 스킬이 건드리는 테이블:

- `project_info` (id=1 singleton) — 프로젝트 경로/cmux workspace/git 환경 (bootstrap, Step 2)
- `project` (id=1 singleton) — PRD 설계 관점의 이름/설명/타임스탬프
- `progress` (phase='prd') — `completed`, `completed_at` 세팅
- `prd` (id=1) — PRD 파일 경로 기록

나머지 테이블(`agents`, `layout_splits`, `local_*`)은 후속 스킬이 채운다.

## Workflow

### Step 0: Verify cmux environment (선결조건 체크)

**반드시 제일 먼저 실행.** 실패 시 이후 단계를 **수행하지 않고 즉시 종료**한다.

```bash
if [ -z "${CMUX_WORKSPACE_ID:-}" ]; then echo "NOT_IN_CMUX"; else cmux ping && echo "CMUX_OK"; fi
```

| 출력 | 동작 |
|------|------|
| `NOT_IN_CMUX` | 안내 메시지 출력 후 **중단** (파일 생성/수정 금지) |
| `cmux ping` 에러 | 안내 메시지 출력 후 **중단** |
| `CMUX_OK` | **Step 1 (project-view wrapper 설치 + 사용자 확인)**로 진행 |

**중단 시 안내 예시:**

```
❌ cmux 환경이 아닙니다.

project:init은 cmux workspace 안에서만 실행할 수 있습니다.
이 스킬은 후속 단계(project:agent, project:reload)와 함께 동작하며,
모든 단계는 cmux 내부 터미널에서 수행되어야 합니다.

해결:
  1. cmux를 실행하세요.
  2. cmux pane 안에서 Claude Code를 다시 시작하세요.
  3. `project init`을 다시 호출하세요.
```

### Step 1: Install project-view wrapper and offer to launch the web UI

**강제 단계 — Step 0 통과 직후 가장 먼저 실행한다. 멱등.**

이 단계는 두 가지 책임을 가진다:

1. `.claude/script/project-view.sh` shell wrapper를 프로젝트에 멱등으로 설치한다.
2. 사용자에게 "지금 project-view 웹 대시보드를 띄울지" **단 한 번** 묻고, "예"이면 build → run → 브라우저 오픈까지 자동 진행한다.

#### 1a. `.claude/script/project-view.sh` 설치 (강제)

caller pane이 다른 작업으로 바쁘거나 슬래시 명령을 입력할 수 없는 상황에서도 `/project-view` 기능을 셸 한 줄로 띄울 수 있도록, 프로젝트 루트의 `.claude/script/`에 wrapper를 복사한다. wrapper는 마켓플레이스 캐시 → `CLAUDE_PLUGIN_ROOT` → `CMUX_WORKSHOP_HOME` 순서로 실제 `start.sh` 위치를 자동 탐색하므로 설치 방식과 무관하게 동작한다.

```bash
SRC="${CLAUDE_PLUGIN_ROOT}/skills/project-init/references/project-view.sh"
DST_DIR="$PWD/.claude/script"
DST="$DST_DIR/project-view.sh"

mkdir -p "$DST_DIR"

# 멱등 복사 — 내용이 동일하면 mtime/권한만 갱신.
if [ ! -f "$DST" ] || ! cmp -s "$SRC" "$DST"; then
    cp "$SRC" "$DST"
    chmod +x "$DST"
    echo "→ .claude/script/project-view.sh 설치/갱신 완료"
else
    chmod +x "$DST"
    echo "→ .claude/script/project-view.sh 최신 상태"
fi
```

**분기 요약:**

| 상태 | 동작 |
|------|------|
| `.claude/script/` 없음 | `mkdir -p`로 생성 → wrapper 복사 |
| wrapper 없음 | 새로 복사 + `chmod +x` |
| wrapper 존재 + 내용 동일 | 권한만 보장(`chmod +x`), 복사 skip |
| wrapper 존재 + 내용 상이 (플러그인 업그레이드 등) | 최신 wrapper로 덮어쓰기 |

**git 정책:** 이 wrapper는 프로젝트와 함께 commit해도 안전하다 — 절대 경로나
머신 로컬 정보를 담지 않고, 동작 시점에 동적으로 플러그인 위치를 해결한다.
다른 머신에서 plugin이 다른 경로에 설치되어 있어도 그대로 작동한다.

#### 1b. project-view 웹 대시보드 자동 기동 여부 확인 (필수 1회)

wrapper 설치 직후 **반드시 한 번** 사용자에게 묻는다 (이 스킬 호출당 1회):

```text
프로젝트 진행 상황(Claude Code/cmux의 hook 이벤트)을 실시간 chat timeline으로
보고 싶다면 지금 project-view 웹 대시보드를 띄울 수 있습니다.

지금 띄울까요? (예 / 아니오)
```

**사용자 응답 분기:**

| 응답 | 동작 |
|------|------|
| 예 / yes / y / 네 | **1c 실행**(빌드 + 기동 + 브라우저 오픈) → 완료/실패 무관하게 Step 2로 진행 |
| 아니오 / no / n | Step 2로 즉시 진행. 안내: "필요할 때 `.claude/script/project-view.sh start`로 언제든 띄울 수 있습니다." |
| 그 외 / 무응답 | 한 번만 더 짧게 재확인 후, 응답이 명확치 않으면 **아니오**로 처리하고 Step 2로 진행 |

이 질문은 **Step 1에서 단 한 번**만 한다. 한 번 거절하면 같은 호출 안에서는 다시 묻지 않는다 (사용자가 직접 wrapper로 띄우거나 `/project-view` 슬래시 명령으로 띄울 수 있음).

#### 1c. 빌드 + 기동 + 브라우저 오픈 (예 분기 전용)

사용자가 "예"라고 답한 경우에만 실행한다. **PRD 작성을 막지 않도록** 60초 timeout 안에서만 시도하고, 실패해도 Step 2로 계속 진행한다.

```bash
RUNTIME="${CLAUDE_PLUGIN_ROOT}/skills/project-view/runtime"

# 1) node_modules가 없으면 1회 자동 설치 (start.sh는 자동 설치하지 않음)
if [ ! -d "$RUNTIME/node_modules" ]; then
    echo "→ runtime/node_modules 없음 — npm install (최초 1회, 약 30~60초)..."
    ( cd "$RUNTIME" && npm install )
fi

# 2) launcher 실행 — start.sh가 dist/index.html 부재 시 npm run build를 자동 수행
#    (출력에서 "READY: <URL>" sentinel을 추출)
LAUNCH_OUT=$(bash "$PWD/.claude/script/project-view.sh" start) || LAUNCH_OUT="$LAUNCH_OUT"
URL=$(printf '%s\n' "$LAUNCH_OUT" | awk '/^READY: /{print $2; exit}')

# 3) READY URL이 잡히면 기본 브라우저로 오픈
if [ -n "${URL:-}" ]; then
    open "$URL"
    echo "✅ project-view 대시보드 오픈: $URL"
else
    echo "⚠️ project-view 기동 실패 — Step 2로 계속 진행합니다."
    echo "   재시도: bash .claude/script/project-view.sh start"
fi
```

`start.sh`가 정상 종료되면 마지막 줄에 다음 형태의 sentinel을 stdout으로 출력한다:

```
READY: http://localhost:11573
```

(포트는 `CMUX_WORKSHOP_SERVER_PORT` env override가 있을 때 해당 값.)

**실패 처리 — 어떤 경우에도 PRD 작성을 막지 않는다:**

| 증상 | 동작 |
|------|------|
| `check-deps.sh` 실패 (Redis/Node/runtime 누락) | 출력된 install hint를 사용자에게 그대로 전달하고 Step 2로 진행 |
| `npm install` 실패 | 마지막 로그를 사용자에게 보여주고 Step 2로 진행 |
| `npm run build` 실패 | start.sh가 vite 출력을 stderr로 노출. 사용자에게 안내 후 Step 2로 진행 |
| 60초 안에 READY 미수신 | start.sh가 마지막 50줄 server log를 stderr로 출력. `references/troubleshooting.md` 안내 후 Step 2로 진행 |

**핵심 원칙:** 1c는 "보조 도구 기동"이므로, 어떤 실패도 메인 워크플로우(PRD 작성)를 막지 않는다. 실패는 사용자에게 보고만 하고 Step 2로 계속 진행한다.

**사용자가 직접 띄우고 싶을 때 (참고):**

```text
프로젝트 루트에서 셸로 직접 실행:
  .claude/script/project-view.sh start    # = /project-view
  .claude/script/project-view.sh stop     # = /project-view-stop
  .claude/script/project-view.sh check    # 의존성 점검만

기본값(다른 dev 서버와 충돌하지 않도록 일부러 흔치 않은 포트):
  CMUX_WORKSHOP_SERVER_PORT   express + ws port  (기본 11573)
  REDIS_URL                   redis://127.0.0.1:6379
  STREAM_KEY                  cmux:hooks

기본 포트가 점유 중이면 start.sh가 자동으로 점유 프로세스를 SIGTERM →
SIGKILL로 회수한 뒤 시작한다. 기존 프로세스를 죽이지 않으려면 환경변수로
다른 포트를 지정해서 실행한다:

  CMUX_WORKSHOP_SERVER_PORT=20013 .claude/script/project-view.sh
```

### Step 2: Bootstrap project.db + project_info (migration 포함)

**강제 단계 — 모든 경로에서 반드시 실행된다.** 여기서 DB 파일과 `project_info`
싱글톤 행이 보장되므로, Step 3 이후 로직은 안전하게 DB를 읽고 쓸 수 있다.

```bash
DB="${CLAUDE_PLUGIN_ROOT}/tools/db.sh"
CAPTURE="${CLAUDE_PLUGIN_ROOT}/tools/scripts/project-info-capture.sh"

# 1. 스키마 보장 (IF NOT EXISTS, 멱등)
"$DB" init

# 2. project_info 싱글톤 존재 여부 확인
HAS_INFO=$("$DB" scalar "SELECT COUNT(*) FROM project_info WHERE id = 1")

if [[ "$HAS_INFO" != "1" ]]; then
    # 신규 생성 또는 기존 프로젝트 migration
    "$CAPTURE" --quiet
    echo "→ project_info 초기화 완료 (migration)"
else
    # 이미 있음 — project_root가 현재 디렉토리와 일치하는지만 검증
    STORED_ROOT=$("$DB" scalar "SELECT project_root FROM project_info WHERE id = 1")
    if [[ "$STORED_ROOT" != "$PWD" ]]; then
        echo "⚠️ project_info.project_root ($STORED_ROOT) != \$PWD ($PWD) — 재캡처합니다"
        "$CAPTURE" --quiet
    fi
fi
```

**분기 요약:**

| 상태 | 동작 |
|------|------|
| DB 파일 없음 | `db.sh migrate`로 스키마 생성/마이그레이션 → `project-info-capture.sh`로 신규 캡처 |
| DB 존재 + `project_info` 비어 있음 (**legacy migration**) | `project-info-capture.sh`로 자동 채움. 기존 `project`/`prd`/`agents`/... 데이터는 건드리지 않음 |
| DB 존재 + `project_info.project_root` != `$PWD` | 경로 변경 감지 → 재캡처 (cmux workspace title 등 갱신) |
| 모두 최신 | 통과 (Step 3으로) |

**이 단계는 절대 skip되지 않는다.** 기존에 이미 PRD/에이전트까지 완료된
프로젝트도 반드시 `project_info` 캡처를 먼저 받고 그 이후에 이 스킬의 나머지
작업이 진행된다.

### Step 3: Check existing PRD status

DB에 기록된 PRD 진행 상태를 조회한다.

```bash
"$DB" json "$(cat "${CLAUDE_PLUGIN_ROOT}/tools/queries/get-progress.sql")"
```

**분기:**

- **PRD 없음 (`progress.prd.completed = 0`)** → Step 4로 진행 (신규/재작성)
- **PRD 완료 (`progress.prd.completed = 1`)** →
  아래 쿼리로 타임스탬프/PRD 경로도 읽어 출력:
  ```bash
  "$DB" json "SELECT p.name, pr.path AS prd_path, pg.completed_at
              FROM project p, prd pr, progress pg
              WHERE p.id=1 AND pr.id=1 AND pg.phase='prd'"
  ```
  ```
  이 프로젝트는 이미 PRD가 작성되어 있습니다:
    - PRD: {prd_path}
    - 작성 시각: {completed_at}

  진행 단계:
    [✅] 1. PRD 작성 완료
    [{agents_mark}] 2. 에이전트 설계
    [{deployed_mark}] 3. cmux 배포

  옵션:
    1) PRD 다시 작성 (기존 내용 덮어씀)
    2) 다음 단계로 진행 → `project:agent`
    3) 취소
  ```
  사용자가 1번을 선택한 경우에만 Step 4로 진행.

### Step 4: Invoke superpowers:brainstorming (강제)

**반드시 `Skill` 도구로 `superpowers:brainstorming` 스킬을 호출한다.** 이 단계를 건너뛰거나 스킬 본문 로직을 복제하지 않는다.

```
Skill(skill="superpowers:brainstorming")
```

`brainstorming` 스킬의 체크리스트(프로젝트 컨텍스트 탐색 → 명확화 질문 → 2~3 접근 제시 → 설계 발표 → 승인)를 **그대로 따른다.**

**이 스킬에서만 적용되는 두 가지 예외:**

1. **Step 6 (Write design doc) 오버라이드**: 설계 문서를 `docs/superpowers/specs/...`가 아니라 `.claude/PRD.md`로 기록한다 (구조는 Step 5 참조). 사용자에게도 "PRD로 저장됩니다"를 명시한다.
2. **Step 9 (Transition to implementation) 오버라이드**: `writing-plans`를 호출하지 않는다. 대신 이 스킬의 Step 7(project.db 갱신) 및 Step 8(`project:agent` 안내)로 이어간다.

사용자가 브레인스토밍 단계에서 설계를 승인할 때까지 **아래 Step 5~7은 실행하지 않는다.** 중단/취소 시에는 파일을 쓰지 않는다.

### Step 5: Convert approved design to PRD

브레인스토밍의 "Write design doc" 타이밍에 도달하면, 승인된 설계를 아래 PRD 구조로 재포맷하여 `.claude/PRD.md`에 기록한다.

**PRD 구조** (`.claude/PRD.md`):

```markdown
# {프로젝트 이름} — PRD

**작성일**: {YYYY-MM-DD}
**버전**: 1.0
**상태**: Draft

## 1. 개요 (Overview)

{프로젝트의 1~2문단 요약 — 무엇을 만드는지, 왜 필요한지}

## 2. 문제 정의 (Problem Statement)

{해결하려는 구체적인 문제 — 현재 상태의 불편함, pain point}

## 3. 목표 (Goals)

### 3.1 주요 목표
- {핵심 목표 1}
- {핵심 목표 2}

### 3.2 성공 지표
- {측정 가능한 기준 1}
- {측정 가능한 기준 2}

## 4. 주 사용자 (Target Users)

- **Primary**: {주 사용자 그룹 — 역할, 요구}
- **Secondary**: {보조 사용자 그룹}

## 5. 사용자 스토리 (User Stories)

- As a {role}, I want to {action} so that {benefit}
- ... (5~10개)

## 6. 핵심 기능 (Core Features)

### 6.1 MVP Features
1. **{기능 이름}** — {설명}
2. ...

### 6.2 Future (out of MVP scope)
- {추후 확장 기능}

## 7. 기술 요구사항 (Technical Requirements)

- **스택**: {감지된 기술 스택}
- **아키텍처**: {구조 개요}
- **의존성**: {외부 시스템, API, 라이브러리}
- **성능**: {응답 시간, 처리량 등}

## 8. 범위 제외 (Out of Scope)

- {명시적으로 다루지 않는 것 1}
- {명시적으로 다루지 않는 것 2}

## 9. 제약 조건 (Constraints)

- {일정}
- {예산/리소스}
- {기술 제약}

## 10. 열린 질문 (Open Questions)

- {추후 해결이 필요한 이슈}
```

**가이드라인:**
- 작성 언어는 사용자의 주 언어를 따른다 (한국어 대화면 한국어로)
- 구체적이고 측정 가능하게 작성
- 추측한 항목은 "TBD" 또는 "Open Questions"에 명시
- 브레인스토밍에서 이미 확정된 내용을 그대로 반영 (재질문 금지)

### Step 6: Write PRD file

```bash
mkdir -p .claude
```

Write 도구로 `.claude/PRD.md`를 작성한다. 작성 후 `brainstorming` 스킬의 **Spec self-review**와 **User reviews written spec** 단계를 그대로 수행한다 (PRD 파일을 대상으로).

### Step 7: Initialize/update project.db

**스키마 생성** (항상 먼저 실행 — 멱등):

```bash
"$DB" migrate
```

이 한 줄로 `.claude/project.db`가 없으면 생성되고, 모든 테이블이 `IF NOT EXISTS`로 만들어진 뒤 pending migration이 적용된다. `progress` 세 행도 `completed=0`으로 시드된다.

**프로젝트 행 작성 (신규 / 재작성 공통)** — `INSERT OR REPLACE`로 upsert:

```bash
NAME=$("$DB" quote "<project-directory-name>")
DESC=$("$DB" quote "<프로젝트 1줄 요약>")

"$DB" exec "INSERT OR REPLACE INTO project
    (id, schema_version, name, description, created_at, updated_at)
    VALUES (1, 4,
            $NAME, $DESC,
            COALESCE((SELECT created_at FROM project WHERE id=1 AND name <> '(uninitialized)'), datetime('now')),
            datetime('now'))"
```

`COALESCE`로 `created_at`은 최초 값 유지, `updated_at`만 현재 시각.

**PRD 파일 기록**:

```bash
PRD_PATH=$("$DB" quote ".claude/PRD.md")

"$DB" exec "INSERT OR REPLACE INTO prd (id, path, created_at)
            VALUES (1, $PRD_PATH, datetime('now'))"
```

**Progress 갱신** (PRD 완료 마킹):

```bash
"$DB" exec "UPDATE progress
            SET completed = 1, completed_at = datetime('now')
            WHERE phase = 'prd'"
```

**PRD 재작성 시**: 동일한 INSERT OR REPLACE/UPDATE가 그대로 적용된다.
`agents`, `layout_splits`, `progress.agents`, `progress.deployed` 테이블은
**건드리지 않는다** — PRD가 크게 바뀌어 에이전트 재설계가 필요하면 사용자에게 안내하되, 자동 리셋은 하지 **않는다**.

쿼리 템플릿 참조: `skills/project-init/scripts/queries/`.

### Step 8: Report and transition to `project:agent`

사용자가 PRD를 최종 승인한 직후 아래 형식으로 보고하고, **자동으로 Phase 2로 전환할지 사용자에게 묻는다.** (writing-plans 호출은 수행하지 않는다 — 이 파이프라인의 "implementation transition"은 에이전트 팀 구성이다.)

```
✅ PRD 작성 완료 (브레인스토밍 기반)

프로젝트: {name}
설명: {description}

생성된 파일:
  - .claude/PRD.md
  - .claude/project.db (SQLite)

진행 단계:
  [✅] 1. PRD 작성
  [  ] 2. 에이전트 설계         ← 다음 단계
  [  ] 3. cmux 배포

👉 다음 단계: 지금 `project:agent`를 실행하여 AI 에이전트 팀을 설계할까요?
   (건너뛰고 나중에 호출해도 됩니다.)
```

사용자가 승인하면 **즉시 `project:agent` 스킬을 호출한다** (Skill 도구 사용). 거부하면 여기서 종료하되, 재개 방법(`project:agent` 호출)을 안내한다.

## Design Notes

- **브레인스토밍 강제 위임**: 아이디어 탐색/질의/설계는 전적으로 `superpowers:brainstorming`이 담당한다. 이 스킬은 그 출력을 PRD로 변환하고 Phase 2로 연결하는 **어댑터**다. 질문 로직이나 설계 승인 절차를 복제하지 않는다.
- **Terminal state 오버라이드**: `brainstorming`의 기본 종착지(`writing-plans`)는 구현 계획용이다. 이 파이프라인에서는 `project:agent`(에이전트 팀 구성)가 구현 전환이므로, 해당 단계를 오버라이드한다.
- **에이전트 구성 없음**: 이 스킬은 PRD에만 집중한다. 에이전트 설계는 `project:agent`에서 수행.
- **cmux 강제**: 파일 자체는 cmux에 의존하지 않지만, 후속 스킬(`project:agent`, `project:reload`)이 cmux를 필수로 하므로 진입 시점에 환경을 차단한다. 잘못된 환경에서 PRD만 생성되고 이후가 막히는 파편화를 방지한다.
- **진행 추적**: `progress.prd.completed`가 이 스킬의 완료 마커이다.
- **멱등성**: 이미 PRD가 있으면 재작성 여부를 사용자에게 확인한다.

## Edge Cases

- **cmux 미실행 / 외부 터미널**: Step 0에서 즉시 차단. 어떤 파일도 생성하지 않는다.
- **`superpowers:brainstorming` 스킬이 설치되지 않음**: 사용자에게 Superpowers 플러그인 설치를 안내하고 중단한다. 자체 브레인스토밍 로직으로 대체하지 않는다.
- **사용자가 브레인스토밍 설계를 끝내 승인하지 않음**: PRD 작성 없이 종료한다 (HARD-GATE 준수).
- **프로젝트가 너무 커서 서브프로젝트 분해 권고**: `brainstorming`이 분해를 안내하면 그 지시를 따른다. 이 경우 PRD는 "첫 번째 서브프로젝트"에 대해 작성된다.
- **빈 디렉토리**: `brainstorming`이 질의응답으로 신규 정의를 주도한다.
- **사용자가 중간에 취소**: 파일을 쓰지 않고 중단한다.
- **PRD가 이미 있음**: 재작성/건너뛰기를 물어본다.

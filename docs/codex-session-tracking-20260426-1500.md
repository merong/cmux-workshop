# codex session tracking report

## 변경 요약

- `local_surfaces`에 CLI session 추적 컬럼 `cli_session_id VARCHAR(255)`, `cli_session_label VARCHAR(255)`, `last_active_at VARCHAR(64)`를 추가했다.
- schema baseline을 version 3으로 올리고 `003_session_tracking.sql` migration을 추가했다.
- `project-reload` v0.7.0에 prior session state 읽기, Claude/Codex resume launch 합성, readiness 후 session id capture, session-aware DB insert/report를 문서화했다.
- `project-status`가 session prefix와 `last_active_at`을 runtime status 데이터로 읽고 표시하도록 갱신했다.
- `project-reset`에 local/full reset 시 session metadata가 삭제되어 다음 reload가 fresh launch가 된다는 안내를 추가했다.
- `project-init`의 project schema_version upsert를 3으로 갱신하고, migration placeholder row의 `created_at`이 실제 프로젝트에 이어지지 않도록 했다.
- marketplace/plugin version을 `0.1.2`로 갱신했다.

## 파일 변경 목록

- `plugins/cmux-workshop/tools/schema.sql:19` — `project.schema_version` default를 3으로 갱신.
- `plugins/cmux-workshop/tools/schema.sql:110` — `local_surfaces.cli_session_id VARCHAR(255)` 추가.
- `plugins/cmux-workshop/tools/schema.sql:111` — `local_surfaces.cli_session_label VARCHAR(255)` 추가.
- `plugins/cmux-workshop/tools/schema.sql:112` — `local_surfaces.last_active_at VARCHAR(64)` 추가.
- `plugins/cmux-workshop/tools/migrations/003_session_tracking.sql` — 신규 migration. session 컬럼을 가진 `local_surfaces` shape로 갱신하고 `project.schema_version=3` 반영.
- `plugins/cmux-workshop/tools/SCHEMA.md:111` — session 컬럼 의미와 NULL 의미 추가.
- `plugins/cmux-workshop/tools/SCHEMA.md:156` — schema-only 검증용 `(uninitialized)` placeholder row 동작 문서화.
- `plugins/cmux-workshop/tools/SCHEMA.md:167` — migration 003 목록 추가.
- `plugins/cmux-workshop/tools/queries/get-surfaces.sql:10` — status query에 session 컬럼 추가.
- `plugins/cmux-workshop/tools/README.md:72` — machine-local zone에 resumable session metadata 설명 추가.
- `plugins/cmux-workshop/skills/project-reload/SKILL.md:15` — `project-reload` version `0.7.0`.
- `plugins/cmux-workshop/skills/project-reload/SKILL.md:95` — Initial Deployment vs Reload에 session resume 동작 추가.
- `plugins/cmux-workshop/skills/project-reload/SKILL.md:131` — Step 3에서 `local_surfaces` prior session state 조회 추가.
- `plugins/cmux-workshop/skills/project-reload/SKILL.md:157` — Step 4.5 effective launch command 합성 규칙 추가.
- `plugins/cmux-workshop/skills/project-reload/SKILL.md:253` — `cmux send`가 `agent.launch_command` 대신 `effective_launch_command`를 쓰도록 갱신.
- `plugins/cmux-workshop/skills/project-reload/SKILL.md:332` — Step 6.10 session id capture 휴리스틱 추가.
- `plugins/cmux-workshop/skills/project-reload/SKILL.md:404` — Step 7 INSERT 컬럼에 session metadata 추가.
- `plugins/cmux-workshop/skills/project-reload/SKILL.md:510` — Step 11 report에 session prefix/empty 표시 추가.
- `plugins/cmux-workshop/skills/project-reload/SKILL.md:582` — Design Notes에 session resume/capture 추가.
- `plugins/cmux-workshop/skills/project-reload/scripts/queries/insert-surface.sql:18` — insert template에 session 컬럼 추가.
- `plugins/cmux-workshop/skills/project-status/SKILL.md:14` — `project-status` version `0.5.1`.
- `plugins/cmux-workshop/skills/project-status/SKILL.md:98` — runtime surfaces + session metadata 조회 추가.
- `plugins/cmux-workshop/skills/project-status/SKILL.md:228` — status 계산에 session id/last active 포함.
- `plugins/cmux-workshop/skills/project-status/SKILL.md:257` — runtime status 표에 Session 컬럼 추가.
- `plugins/cmux-workshop/skills/project-init/scripts/workspace-status.sh:64` — session 컬럼 존재 여부 확인 후 JSON 출력에 session fields 포함.
- `plugins/cmux-workshop/skills/project-reset/SKILL.md:12` — `project-reset` version `0.4.1`.
- `plugins/cmux-workshop/skills/project-reset/SKILL.md:56` — reset mode 표에 session metadata 삭제/fresh launch 안내 추가.
- `plugins/cmux-workshop/skills/project-reset/SKILL.md:186` — local reset이 session 컬럼도 삭제함을 명시.
- `plugins/cmux-workshop/skills/project-init/SKILL.md:15` — `project-init` version `0.7.1`.
- `plugins/cmux-workshop/skills/project-init/scripts/queries/upsert-project.sql:11` — project row schema_version을 3으로 갱신.
- `.claude-plugin/marketplace.json:12` — marketplace plugin version `0.1.2`.
- `plugins/cmux-workshop/.claude-plugin/plugin.json:3` — plugin version `0.1.2`.

## 검증 결과

JSON:

```text
.claude-plugin/marketplace.json OK
plugins/cmux-workshop/.claude-plugin/plugin.json OK
plugins/cmux-workshop/hooks/hooks.json OK
```

Bash syntax:

```text
syntax OK: plugins/cmux-workshop/tools/db.sh
syntax OK: plugins/cmux-workshop/tools/scripts/project-info-show.sh
syntax OK: plugins/cmux-workshop/tools/scripts/project-info-capture.sh
syntax OK: plugins/cmux-workshop/hooks/scripts/block-dangerous.sh
syntax OK: plugins/cmux-workshop/hooks/scripts/save-conv-before-commit.sh
syntax OK: plugins/cmux-workshop/skills/project-view/scripts/helpers.sh
syntax OK: plugins/cmux-workshop/skills/project-view/scripts/check-deps.sh
syntax OK: plugins/cmux-workshop/skills/project-view/scripts/stop.sh
syntax OK: plugins/cmux-workshop/skills/project-view/scripts/start.sh
syntax OK: plugins/cmux-workshop/skills/project-reload/scripts/verify-pane-ready.sh
syntax OK: plugins/cmux-workshop/skills/project-agent/scripts/agent-list.sh
syntax OK: plugins/cmux-workshop/skills/project-agent/scripts/agent-fetch.sh
syntax OK: plugins/cmux-workshop/skills/project-init/scripts/workspace-info.sh
syntax OK: plugins/cmux-workshop/skills/project-init/scripts/workspace-status.sh
```

SQL parse:

```text
memory
schema parses
```

Baseline + migrations:

```text
delete
delete
applied: plugins/cmux-workshop/tools/migrations/001_init.sql
applied: plugins/cmux-workshop/tools/migrations/002_local_surfaces_error.sql
applied: plugins/cmux-workshop/tools/migrations/003_session_tracking.sql
3
    cli_session_id    VARCHAR(255),
    cli_session_label VARCHAR(255),
    last_active_at    VARCHAR(64),
```

추가 smoke check (`db.sh migrate` on temp DB):

```text
delete
3
3
3
```

위 세 줄은 순서대로 `metadata.schema_version`, `project.schema_version`, `local_surfaces` session 컬럼 개수다.

## 잔여 위험 / 후속 과제

- 실제 cmux/Claude/Codex pane에서 session capture/resume end-to-end는 실행하지 않았다. 이번 검증은 명세 범위의 JSON/shell/SQL parse와 migration smoke check까지다.
- SQLite에는 `ALTER TABLE ADD COLUMN IF NOT EXISTS`가 없어, `003_session_tracking.sql`은 최신 `schema.sql` 위에 모든 migration을 재적용하는 검증을 통과하도록 `local_surfaces`를 003 shape로 재구성한다. versioned migration 경로에서는 nullable 컬럼 추가와 같은 결과다.
- Codex session capture 휴리스틱은 명세대로 `$HOME/.codex/sessions`의 최신 항목을 사용한다. Codex가 nested session directory를 쓰는 환경이면 후속 보강이 필요할 수 있다.
- Claude/Codex session 파일이 삭제된 경우 fresh fallback으로 문서화했지만, 실제 구현자는 파일 존재 검사와 launch 로그를 SKILL 절차대로 빠짐없이 반영해야 한다.

## 다음 코드 리뷰 권장 영역

- `project-reload` 실제 실행 경로에서 prior_state → effective_launch_command → capture → Step 7 INSERT가 빠짐없이 구현되는지 dry-run fixture로 검증.
- Claude/Codex 최신 session file 경로가 현재 설치 버전과 맞는지 실제 머신에서 확인.
- `workspace-status.sh` JSON 출력이 `project-status` 표 렌더링과 맞는지 cmux tree 샘플로 테스트.
- Migration 003이 기존 v2 DB의 `local_surfaces` 데이터를 보존하면서 새 session 컬럼을 NULL로 추가하는지 fixture DB로 재확인.
END-OF-REPORT

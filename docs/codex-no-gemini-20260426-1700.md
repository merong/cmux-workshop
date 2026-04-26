# codex no-gemini report

## 변경 요약

- Agent CLI 매트릭스를 `claude`, `codex`, `custom`만 허용하도록 정리했다.
- `agents.type` baseline CHECK를 `('claude','codex','custom')`로 강화하고 schema version을 4로 올렸다.
- migration 004를 추가해 기존 `gemini` row를 삭제하지 않고 `codex` row로 변환한다.
- `project-agent`에서 Gemini CLI 추천/예시를 제거하고 reviewer, architect/design/frontend 기본 추천을 `codex`로 정리했다.
- `project-reload`, `project-status`, `cmux` 문서와 readiness helper에서 Gemini 분기/예시를 제거했다.
- 6개 persona frontmatter에 `recommended_cli`를 추가했다.
- marketplace/plugin lockstep version을 `0.1.4`로 갱신했다.

## 파일 변경 목록

- `plugins/cmux-workshop/tools/schema.sql:19` — `project.schema_version` default를 4로 갱신.
- `plugins/cmux-workshop/tools/schema.sql:45` — `agents.type` CHECK를 `claude/codex/custom`으로 제한.
- `plugins/cmux-workshop/tools/migrations/004_drop_gemini_agent_type.sql` — 신규 migration. legacy unsupported CLI row를 `codex`로 보존 변환하고 schema_version 4 반영.
- `plugins/cmux-workshop/tools/SCHEMA.md:43` — `agents.type` enum에서 unsupported CLI 제거.
- `plugins/cmux-workshop/tools/SCHEMA.md:169` — migration 004 절차 추가.
- `plugins/cmux-workshop/skills/project-agent/SKILL.md:18` — version `0.6.0`.
- `plugins/cmux-workshop/skills/project-agent/SKILL.md:149` — CLI matrix를 `claude`/`codex` 중심으로 교체.
- `plugins/cmux-workshop/skills/project-agent/SKILL.md:154` — persona → CLI 기본 매핑 추가.
- `plugins/cmux-workshop/skills/project-agent/SKILL.md:326` — reviewer 예시를 `codex --full-auto`로 변경.
- `plugins/cmux-workshop/skills/project-agent/scripts/queries/insert-agent.sql:7` — insert template enum 주석에서 unsupported CLI 제거.
- `plugins/cmux-workshop/skills/project-reload/SKILL.md:15` — version `0.7.1`.
- `plugins/cmux-workshop/skills/project-reload/SKILL.md:148` — CLI availability 예시에서 unsupported CLI 검사 제거.
- `plugins/cmux-workshop/skills/project-reload/SKILL.md:193` — launch command fallback 설명을 `custom` 중심으로 갱신.
- `plugins/cmux-workshop/skills/project-reload/SKILL.md:523` — reviewer 예시 모델을 `GPT-5.x`로 변경.
- `plugins/cmux-workshop/skills/project-reload/scripts/verify-pane-ready.sh:7` — `--cli` usage를 `claude|codex|custom`으로 변경.
- `plugins/cmux-workshop/skills/project-status/SKILL.md:14` — version `0.5.2`.
- `plugins/cmux-workshop/skills/project-status/SKILL.md:172` — reviewer 설계 예시를 `codex`로 변경.
- `plugins/cmux-workshop/skills/project-status/SKILL.md:251` — runtime command 예시를 `codex --full-auto`로 변경.
- `plugins/cmux-workshop/skills/cmux/SKILL.md:14` — version `0.2.1`.
- `plugins/cmux-workshop/skills/cmux/SKILL.md:140` — TUI CLI 설명을 Claude Code/Codex로 정리.
- `plugins/cmux-workshop/skills/project-init/SKILL.md:18` — version `0.7.3`, project schema_version upsert 4 반영.
- `plugins/cmux-workshop/skills/project-init/references/cmux-cli-reference.md:134` — TUI CLI 설명을 Claude Code/Codex로 정리.
- `plugins/cmux-workshop/skills/project-init/scripts/queries/upsert-project.sql:11` — project row schema_version 4 반영.
- `plugins/cmux-workshop/AGENTS.md:4` — specialist CLI 목록을 Codex/Claude로 정리.
- `plugins/cmux-workshop/agents/architect.md:5` — `recommended_cli: codex` 추가.
- `plugins/cmux-workshop/agents/debugger.md:5` — `recommended_cli: claude` 추가.
- `plugins/cmux-workshop/agents/implementer.md:5` — `recommended_cli: codex` 추가.
- `plugins/cmux-workshop/agents/orchestrator.md:5` — `recommended_cli: claude` 추가.
- `plugins/cmux-workshop/agents/researcher.md:5` — `recommended_cli: claude` 추가.
- `plugins/cmux-workshop/agents/reviewer.md:5` — `recommended_cli: codex` 추가.
- `README-ko.md:604` — schema diagram의 agent type enum을 `claude|codex|custom`으로 갱신.
- `.claude-plugin/marketplace.json:12` — plugin version `0.1.4`.
- `plugins/cmux-workshop/.claude-plugin/plugin.json:3` — plugin version `0.1.4`.

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
syntax OK: plugins/cmux-workshop/skills/project-init/references/project-view.sh
syntax OK: plugins/cmux-workshop/skills/project-init/scripts/workspace-info.sh
syntax OK: plugins/cmux-workshop/skills/project-init/scripts/workspace-status.sh
```

Schema parse:

```text
memory
schema parses
```

Baseline + all migrations:

```text
applied: plugins/cmux-workshop/tools/migrations/001_init.sql
applied: plugins/cmux-workshop/tools/migrations/002_local_surfaces_error.sql
applied: plugins/cmux-workshop/tools/migrations/003_session_tracking.sql
applied: plugins/cmux-workshop/tools/migrations/004_drop_gemini_agent_type.sql
4
    type           TEXT    NOT NULL CHECK (type IN ('claude', 'codex', 'custom')),
agents has gemini? 0
```

Legacy fixture migration:

```text
codex|codex|codex --full-auto|GPT-5.x
4
```

Active docs/skills/personas scan:

```text
rg -n "gemini|Gemini" plugins/cmux-workshop/skills plugins/cmux-workshop/agents plugins/cmux-workshop/AGENTS.md README.md README-ko.md CLAUDE.md .claude-plugin
# no matches
```

## 잔여 위험 / 후속 과제

- `004_drop_gemini_agent_type.sql` necessarily contains the legacy string it rewrites. Active SKILL/AGENTS/persona/README/manifest content no longer advertises or recommends that CLI.
- Migration 004 updates legacy `cli_binary`, exact legacy `launch_command`, and `Gemini%` model strings to Codex defaults. Unusual custom launch strings containing unsupported CLI names may still need manual review.
- End-to-end `project-agent` and `project-reload` were not run because this task forbids dependency/install side effects and the requested validation is static/schema-level.

## 다음 코드 리뷰 권장 영역

- Run `project-agent` on a fixture PRD and confirm role-to-CLI defaults: reviewer/architect/frontend -> `codex`, debugger/researcher/orchestrator -> `claude`.
- Test migration 004 against a real pre-0.1.4 project.db that contains multiple legacy rows and layout_splits references.
- Add a small schema regression test to ensure `agents.type='gemini'` insert fails on a v4 DB while migration conversion preserves old rows as `codex`.
END-OF-REPORT

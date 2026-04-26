# project.db Schema

Single SQLite database at `.claude/project.db`. Split into two zones by naming
convention: plain name = portable, `local_*` prefix = machine-local (cmux
runtime).

## Portable zone (git-tracked)

### `project` (1 row, `id = 1`)
| Column | Type | Notes |
|--------|------|-------|
| `id`               | INTEGER | Always `1` (singleton) |
| `schema_version`   | INTEGER | Current schema version mirrored from `metadata.schema_version` |
| `name`             | TEXT    | Project name |
| `description`      | TEXT    | Free-form |
| `created_at`       | TEXT    | ISO-8601 |
| `updated_at`       | TEXT    | ISO-8601 |

### `progress` (3 rows, pre-seeded)
| Column | Type | Notes |
|--------|------|-------|
| `phase`        | TEXT    | `'prd'` / `'agents'` / `'deployed'` |
| `completed`    | INTEGER | 0 or 1 |
| `completed_at` | TEXT    | ISO-8601 or NULL |

Schema.sql seeds all three rows with `completed = 0`, so `UPDATE` always hits.

### `prd` (1 row, `id = 1`)
| Column | Type | Notes |
|--------|------|-------|
| `id`         | INTEGER | Always `1` |
| `path`       | TEXT    | Relative, e.g. `.claude/PRD.md` |
| `created_at` | TEXT    | ISO-8601 |

The PRD document itself stays as a markdown file for editability. Only the
pointer lives in the DB.

### `agents`
| Column | Type | Notes |
|--------|------|-------|
| `id`             | TEXT PK | English slug, matches `local_surfaces.agent_id` |
| `name`           | TEXT    | Display name + cmux tab title |
| `type`           | TEXT    | `'claude'` / `'codex'` / `'custom'` |
| `role`           | TEXT    | e.g. `'orchestrator'`, `'implementer'` |
| `model`          | TEXT    | e.g. `'Opus 4.6'` |
| `agent_file`     | TEXT    | Relative path to persona `.md` (e.g. `.claude/agents/implementer.md`) |
| `source_type`    | TEXT    | `'local-library'` / `'voltagent'` / `'custom'` |
| `source_origin`  | TEXT    | Origin path/URL of the persona |
| `launch_command` | TEXT    | `NULL` for caller |
| `cli_binary`     | TEXT    | For `command -v` check |
| `is_caller`      | INTEGER | 0 or 1. Only one row should be 1 |
| `position`       | INTEGER | Display order |

The persona markdown file stays on disk; `agent_file` is just a pointer.

### `layout_splits`
| Column | Type | Notes |
|--------|------|-------|
| `position`      | INTEGER PK | Execution order (0..N) |
| `agent_id`      | TEXT FK    | → `agents.id` (CASCADE on delete) |
| `direction`     | TEXT       | `'left'` / `'right'` / `'up'` / `'down'` |
| `from_agent_id` | TEXT       | References an agent id (not a hard FK — caller bootstraps) |

### `project_info` (1 row, `id = 1`)
Runtime environment snapshot — the "where + what" of this project. Populated
by `tools/scripts/project-info-capture.sh`, read by `project-info-show.sh`
and by any skill that needs the project root or cmux workspace binding.

| Column | Type | Notes |
|--------|------|-------|
| `id`                    | INTEGER | Always `1` |
| `project_name`          | TEXT    | Display name (defaults to `basename $project_root`) |
| `project_summary`       | TEXT    | One-line summary (optional) |
| `project_root`          | TEXT    | Absolute path at capture time |
| `cmux_workspace_id`     | TEXT    | e.g. `workspace:7` — NULL when captured outside cmux |
| `cmux_workspace_title`  | TEXT    | cmux tab/workspace title |
| `cmux_socket_path`      | TEXT    | `CMUX_SOCKET_PATH` env at capture time |
| `git_remote_url`        | TEXT    | `origin` remote URL if git repo |
| `git_branch`            | TEXT    | Current branch if git repo |
| `captured_at`           | TEXT    | When capture ran |
| `created_at`            | TEXT    | First insertion (preserved across re-captures) |
| `updated_at`            | TEXT    | Last upsert |

Distinct from the `project` table: `project` holds the PRD-driven design
metadata (name / description chosen during Phase 1), while `project_info`
holds the actual runtime binding (filesystem path, cmux workspace, git
remote). They can drift — e.g. the same repo cloned on two machines gets
different `project_info` rows but the same `project`.

### `metadata`
Free-form key/value for future expansion. Both columns are TEXT.

## Machine-local zone (don't rely on cross-machine)

### `local_workspace` (1 row, `id = 1`)
| Column | Type | Notes |
|--------|------|-------|
| `id`           | INTEGER | Always `1` |
| `workspace_id` | TEXT    | cmux workspace ref (e.g. `workspace:7`) |
| `created_at`   | TEXT    | Deployment time |
| `updated_at`   | TEXT    | Last reload time |

### `local_surfaces`
| Column | Type | Notes |
|--------|------|-------|
| `agent_id`   | TEXT PK FK | → `agents.id` (CASCADE) |
| `surface_id` | TEXT       | cmux surface ref |
| `pane_id`    | TEXT       | cmux pane ref |
| `tab_title`  | TEXT       | Set via `cmux rename-tab` |
| `status`     | TEXT       | `'running'` / `'stopped'` / `'skipped'` / `'error'` |
| `cli_session_id` | VARCHAR(255) | Claude/Codex session id captured after launch/resume |
| `cli_session_label` | VARCHAR(255) | Optional human-readable session label, usually the agent name |
| `last_active_at` | VARCHAR(64) | Last time `project:reload` observed or captured the session |
| `updated_at` | TEXT       | ISO-8601 |

Session columns are nullable. `NULL` means the agent type does not expose a
resumable CLI session, the pane was skipped, or the capture heuristic could not
find a session file. `project:reload` preserves prior session ids for existing
panes, resumes Claude/Codex panes when a session id is present, and records
`last_active_at = datetime('now')` after a successful observation/capture.

### `local_kv`
Free-form key/value for machine-local use (e.g. caching CLI detection).

## Conventions

- `updated_at` is always caller-set (`datetime('now')` in SQLite literal).
- ISO-8601 strings in UTC. Use `strftime('%Y-%m-%dT%H:%M:%fZ', 'now')` for
  millisecond-precision timestamps if needed.
- Foreign keys are connection-local in SQLite. `tools/db.sh` prepends
  `PRAGMA foreign_keys=ON` for every `exec`, `query`, `json`, `scalar`, and
  `run` invocation so cascades work outside the initial schema load too.
- `PRAGMA journal_mode = DELETE` — WAL을 쓰지 않는다. 단일 사용자가 순차적으로
  접근하는 워크로드라 WAL의 동시성 이득이 없고, `.db-wal`/`.db-shm` 사이드카
  파일이 git 상태를 더럽히는 비용이 더 크다. 기존에 WAL 모드였던 DB는
  `tools/db.sh migrate`를 재실행하면 rollback journal로 전환된다.

## Migrations

Schema changes live in `tools/migrations/NNN_name.sql` and are applied in
numeric order by:

```bash
tools/db.sh migrate
```

`migrate` first runs `schema.sql` so missing tables are created, then reads
`metadata.schema_version`. If that metadata key is absent, it falls back to
`project.schema_version`; if neither exists, it records version `1` and applies
forward migrations beginning at `002`.

After each migration file succeeds, `metadata.schema_version` is updated to the
file number and `project.schema_version` is mirrored when the singleton project
row exists.

Migration `003` creates a `(id=1, name='(uninitialized)')` project row only when
the table is empty so schema-only verification can report a concrete
`schema_version`. Migration `004` advances that placeholder to version 4.
`project:init` replaces that placeholder and resets `created_at` for the real
project row.

Current migrations:

| Version | File | Purpose |
|---:|---|---|
| 001 | `tools/migrations/001_init.sql` | Historical 0.1.0 baseline reference |
| 002 | `tools/migrations/002_local_surfaces_error.sql` | Rebuild `local_surfaces` so `status='error'` is accepted |
| 003 | `tools/migrations/003_session_tracking.sql` | Add nullable CLI session tracking columns to `local_surfaces` |
| 004 | `tools/migrations/004_drop_gemini_agent_type.sql` | Rebuild `agents` so `type` is `claude/codex/custom`; legacy unsupported CLI rows become `codex` |

## Zone reset playbooks

```bash
# Before project:reload (drop stale cmux IDs)
tools/db.sh run plugins/cmux-workshop/tools/queries/reset-local.sql

# Before project:reset (drop project entirely, keep schema)
tools/db.sh run plugins/cmux-workshop/tools/queries/reset-portable.sql
tools/db.sh run plugins/cmux-workshop/tools/queries/reset-local.sql
```

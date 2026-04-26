# cmux-workshop tools/

Shared SQLite tooling for the cmux-workshop plugin. All project skills (`project-init`,
`project-agent`, `project-reload`, `project-status`, `project-reset`) read and
write their metadata through `tools/db.sh` against `.claude/project.db`.

## Files

| File | Purpose |
|------|---------|
| `db.sh`                           | sqlite3 wrapper (init / migrate / exec / query / json / scalar / run / quote) |
| `schema.sql`                      | DDL for all tables (idempotent, `IF NOT EXISTS`) |
| `migrations/*.sql`                | Ordered schema migrations applied by `db.sh migrate` |
| `queries/*.sql`                   | Read-only queries reused across skills |
| `scripts/project-info-capture.sh` | Snapshot project path + cmux workspace + git info into `project_info` |
| `scripts/project-info-show.sh`    | Pretty-print or JSON-emit the current `project_info` row |
| `SCHEMA.md`                       | Human-readable description of every table + column |

Skill-local SQL (INSERTs, UPDATEs, bespoke SELECTs) lives under each skill's
`skills/<name>/scripts/queries/`, *not* here.

## project_info capture/show

```bash
# Capture the current project + cmux environment (safe to re-run; upserts a single row)
plugins/cmux-workshop/tools/scripts/project-info-capture.sh \
    --summary "short one-liner"

# Inspect
plugins/cmux-workshop/tools/scripts/project-info-show.sh           # table view
plugins/cmux-workshop/tools/scripts/project-info-show.sh --json    # JSON array
```

Works whether or not you're inside cmux — cmux fields fall back to NULL when
`CMUX_WORKSPACE_ID` is unset. Git fields fall back to NULL when the directory
isn't a git repo.

## db.sh cheat-sheet

```bash
# Absolute path resolution: $CMUX_WORKSHOP_DB_PATH or $PWD/.claude/project.db
tools/db.sh path            # => /path/to/.claude/project.db
tools/db.sh exists          # exit 0 if file exists, 1 otherwise
tools/db.sh migrate         # create schema + apply pending migrations
tools/db.sh init            # create schema only (safe to re-run; migrate is preferred)

# Read
tools/db.sh query "SELECT * FROM agents"                   # pipe-delimited + header
tools/db.sh json  "$(cat tools/queries/get-agents.sql)"    # JSON array of objects
tools/db.sh scalar "SELECT completed FROM progress WHERE phase='prd'"

# Write — prefer heredocs for multi-statement INSERT/UPDATE
tools/db.sh exec "UPDATE progress SET completed=1, completed_at='2026-04-13T10:00:00Z' WHERE phase='prd'"
tools/db.sh run plugins/cmux-workshop/tools/queries/reset-local.sql

# Quoting user-supplied strings (always single-source of escape)
QNAME=$(tools/db.sh quote "user's project")   # => 'user''s project'
tools/db.sh exec "INSERT INTO project (id, name, created_at, updated_at) VALUES (1, $QNAME, datetime('now'), datetime('now'))"
```

## SQL injection rule

`db.sh quote` is the **only** way to embed untrusted strings in SQL. Never
concatenate raw user input. For numeric fields, validate with a regex before
substitution.

## Two zones

- **Portable** — `project`, `progress`, `prd`, `agents`, `layout_splits`,
  `metadata`. Git-tracked; survives machine migration.
- **Machine-local** — `local_workspace`, `local_surfaces`, `local_kv`. Holds
  cmux runtime IDs and resumable Claude/Codex session metadata that change on
  every restart. Wiped by `reset-local.sql` before every `project:reload`, then
  reinserted from the current cmux tree plus cached prior session state.

Keeping both zones in the same db keeps things simple (one file to track),
but commits of `project.db` should ideally happen after
`tools/db.sh run plugins/cmux-workshop/tools/queries/reset-local.sql` so local state
doesn't leak across machines.

## Adding a new skill

1. Create `skills/<your-skill>/scripts/queries/<name>.sql`.
2. Call `db.sh` from the SKILL.md workflow section.
3. If you need a brand-new table, add it to `tools/schema.sql` (append, don't
   rewrite existing tables), add an ordered migration in `tools/migrations/`,
   and document it in `SCHEMA.md`.

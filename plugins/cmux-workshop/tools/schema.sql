-- cmux-workshop plugin project.db schema
--
-- Split into two logical zones:
--   Portable (git-safe)  : project, progress, prd, agents, layout_splits, metadata
--   Machine-local        : local_workspace, local_surfaces (cmux runtime IDs)
--
-- Run via tools/db.sh migrate. Safe to re-run (IF NOT EXISTS everywhere).

PRAGMA foreign_keys = ON;
-- 단일 사용자 전용 DB이므로 WAL 비활성. DELETE(기본 rollback journal)로
-- 유지하여 .db-wal/.db-shm 부산물 없이 단일 .db 파일만 남기고,
-- git 커밋/머신 이동 시 사이드카 파일 관리 부담을 제거한다.
PRAGMA journal_mode = DELETE;

-- ---------- PORTABLE ZONE ----------

CREATE TABLE IF NOT EXISTS project (
    id          INTEGER PRIMARY KEY CHECK (id = 1),  -- single-row table
    schema_version INTEGER NOT NULL DEFAULT 3,
    name        TEXT    NOT NULL,
    description TEXT,
    created_at  TEXT    NOT NULL,
    updated_at  TEXT    NOT NULL
);

CREATE TABLE IF NOT EXISTS progress (
    phase        TEXT PRIMARY KEY CHECK (phase IN ('prd', 'agents', 'deployed')),
    completed    INTEGER NOT NULL DEFAULT 0 CHECK (completed IN (0, 1)),
    completed_at TEXT
);

-- Seed progress rows so UPDATE always hits
INSERT OR IGNORE INTO progress (phase, completed) VALUES
    ('prd', 0), ('agents', 0), ('deployed', 0);

CREATE TABLE IF NOT EXISTS prd (
    id         INTEGER PRIMARY KEY CHECK (id = 1),
    path       TEXT NOT NULL,
    created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS agents (
    id             TEXT PRIMARY KEY,
    name           TEXT    NOT NULL,
    type           TEXT    NOT NULL,           -- 'claude' | 'codex' | 'gemini' | 'custom'
    role           TEXT,
    model          TEXT,
    agent_file     TEXT,                       -- relative path, e.g. '.claude/agents/implementer.md'
    source_type    TEXT    NOT NULL CHECK (source_type IN ('local-library', 'voltagent', 'custom')),
    source_origin  TEXT,                       -- plugin path, github url, or free-form
    launch_command TEXT,                       -- NULL for caller
    cli_binary     TEXT,                       -- for command -v check
    is_caller      INTEGER NOT NULL DEFAULT 0 CHECK (is_caller IN (0, 1)),
    position       INTEGER NOT NULL            -- display order
);

CREATE INDEX IF NOT EXISTS idx_agents_position ON agents(position);

CREATE TABLE IF NOT EXISTS layout_splits (
    position      INTEGER PRIMARY KEY,         -- execution order (0..N)
    agent_id      TEXT NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
    direction     TEXT NOT NULL CHECK (direction IN ('left', 'right', 'up', 'down')),
    from_agent_id TEXT NOT NULL                -- references agents.id (not FK: caller may bootstrap)
);

CREATE INDEX IF NOT EXISTS idx_layout_agent ON layout_splits(agent_id);

-- Runtime environment snapshot: project path + cmux workspace binding + git info.
-- Single row (id = 1). Captured via tools/scripts/project-info-capture.sh.
-- Portable-ish: rows are portable in intent (path is absolute) but typically
-- committed only as a rough reference; re-capture on each machine.
CREATE TABLE IF NOT EXISTS project_info (
    id                   INTEGER PRIMARY KEY CHECK (id = 1),
    project_name         TEXT NOT NULL,             -- display name (often basename of root)
    project_summary      TEXT,                      -- one-line summary
    project_root         TEXT NOT NULL,             -- absolute path
    cmux_workspace_id    TEXT,                      -- e.g. 'workspace:7' (may be NULL if captured outside cmux)
    cmux_workspace_title TEXT,                      -- cmux tab title
    cmux_socket_path     TEXT,                      -- CMUX_SOCKET_PATH at capture time
    git_remote_url       TEXT,                      -- origin remote, if git repo
    git_branch           TEXT,                      -- current branch, if git repo
    captured_at          TEXT NOT NULL,             -- when the capture ran
    created_at           TEXT NOT NULL,
    updated_at           TEXT NOT NULL
);

-- Free-form extensibility (portable). For local metadata use local_kv.
CREATE TABLE IF NOT EXISTS metadata (
    key   TEXT PRIMARY KEY,
    value TEXT
);

-- ---------- MACHINE-LOCAL ZONE ----------
-- These tables track cmux runtime state. Values change on every cmux restart.
-- Convention: keep committed rows empty or let users gitignore via sqldiff workflow.

CREATE TABLE IF NOT EXISTS local_workspace (
    id           INTEGER PRIMARY KEY CHECK (id = 1),
    workspace_id TEXT,
    created_at   TEXT,
    updated_at   TEXT
);

CREATE TABLE IF NOT EXISTS local_surfaces (
    agent_id          TEXT PRIMARY KEY REFERENCES agents(id) ON DELETE CASCADE,
    surface_id        TEXT,
    pane_id           TEXT,
    tab_title         TEXT,
    status            TEXT NOT NULL CHECK (status IN ('running', 'stopped', 'skipped', 'error')),
    cli_session_id    VARCHAR(255),
    cli_session_label VARCHAR(255),
    last_active_at    VARCHAR(64),
    updated_at        TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS local_kv (
    key   TEXT PRIMARY KEY,
    value TEXT
);

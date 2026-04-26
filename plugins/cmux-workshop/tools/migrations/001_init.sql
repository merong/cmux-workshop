-- Migration 001: baseline schema reference for databases created by
-- cmux-workshop 0.1.0. Kept as a historical reference; db.sh migrate treats
-- schema_version 1 as already applied and starts forward migrations at 002.

PRAGMA foreign_keys = ON;
PRAGMA journal_mode = DELETE;

CREATE TABLE IF NOT EXISTS project (
    id          INTEGER PRIMARY KEY CHECK (id = 1),
    schema_version INTEGER NOT NULL DEFAULT 1,
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
    type           TEXT    NOT NULL,
    role           TEXT,
    model          TEXT,
    agent_file     TEXT,
    source_type    TEXT    NOT NULL CHECK (source_type IN ('local-library', 'voltagent', 'custom')),
    source_origin  TEXT,
    launch_command TEXT,
    cli_binary     TEXT,
    is_caller      INTEGER NOT NULL DEFAULT 0 CHECK (is_caller IN (0, 1)),
    position       INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_agents_position ON agents(position);

CREATE TABLE IF NOT EXISTS layout_splits (
    position      INTEGER PRIMARY KEY,
    agent_id      TEXT NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
    direction     TEXT NOT NULL CHECK (direction IN ('left', 'right', 'up', 'down')),
    from_agent_id TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_layout_agent ON layout_splits(agent_id);

CREATE TABLE IF NOT EXISTS project_info (
    id                   INTEGER PRIMARY KEY CHECK (id = 1),
    project_name         TEXT NOT NULL,
    project_summary      TEXT,
    project_root         TEXT NOT NULL,
    cmux_workspace_id    TEXT,
    cmux_workspace_title TEXT,
    cmux_socket_path     TEXT,
    git_remote_url       TEXT,
    git_branch           TEXT,
    captured_at          TEXT NOT NULL,
    created_at           TEXT NOT NULL,
    updated_at           TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS metadata (
    key   TEXT PRIMARY KEY,
    value TEXT
);

CREATE TABLE IF NOT EXISTS local_workspace (
    id           INTEGER PRIMARY KEY CHECK (id = 1),
    workspace_id TEXT,
    created_at   TEXT,
    updated_at   TEXT
);

CREATE TABLE IF NOT EXISTS local_surfaces (
    agent_id   TEXT PRIMARY KEY REFERENCES agents(id) ON DELETE CASCADE,
    surface_id TEXT,
    pane_id    TEXT,
    tab_title  TEXT,
    status     TEXT NOT NULL CHECK (status IN ('running', 'stopped', 'skipped')),
    updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS local_kv (
    key   TEXT PRIMARY KEY,
    value TEXT
);

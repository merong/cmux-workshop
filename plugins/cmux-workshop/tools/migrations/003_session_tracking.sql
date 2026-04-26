-- Migration 003: track resumable CLI sessions on local_surfaces.
--
-- Intended shape:
--   cli_session_id    VARCHAR(255)
--   cli_session_label VARCHAR(255)
--   last_active_at    VARCHAR(64)
--
-- SQLite has no ADD COLUMN IF NOT EXISTS. The repo verification applies every
-- migration on top of the latest schema baseline, so this migration rebuilds
-- local_surfaces with the 003 shape instead of failing on duplicate columns.
-- For a versioned 002 database, the result is equivalent to adding the three
-- nullable columns with default NULL.

PRAGMA foreign_keys=OFF;

BEGIN;

DROP TABLE IF EXISTS local_surfaces_003;

CREATE TABLE local_surfaces_003 (
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

INSERT OR REPLACE INTO local_surfaces_003 (
    agent_id,
    surface_id,
    pane_id,
    tab_title,
    status,
    cli_session_id,
    cli_session_label,
    last_active_at,
    updated_at
)
SELECT
    agent_id,
    surface_id,
    pane_id,
    tab_title,
    status,
    NULL,
    NULL,
    NULL,
    updated_at
  FROM local_surfaces;

DROP TABLE local_surfaces;
ALTER TABLE local_surfaces_003 RENAME TO local_surfaces;

INSERT OR IGNORE INTO project (id, schema_version, name, description, created_at, updated_at)
VALUES (1, 3, '(uninitialized)', NULL, datetime('now'), datetime('now'));

UPDATE project SET schema_version = 3 WHERE id = 1;

COMMIT;

PRAGMA foreign_keys=ON;

-- Migration 002: allow local_surfaces.status='error' for panes that exist but
-- fail readiness/authentication checks.

PRAGMA foreign_keys=OFF;

BEGIN;

DROP TABLE IF EXISTS local_surfaces_new;

CREATE TABLE local_surfaces_new (
    agent_id   TEXT PRIMARY KEY REFERENCES agents(id) ON DELETE CASCADE,
    surface_id TEXT,
    pane_id    TEXT,
    tab_title  TEXT,
    status     TEXT NOT NULL CHECK (status IN ('running', 'stopped', 'skipped', 'error')),
    updated_at TEXT NOT NULL
);

INSERT OR REPLACE INTO local_surfaces_new (agent_id, surface_id, pane_id, tab_title, status, updated_at)
SELECT agent_id, surface_id, pane_id, tab_title, status, updated_at
  FROM local_surfaces;

DROP TABLE local_surfaces;
ALTER TABLE local_surfaces_new RENAME TO local_surfaces;

COMMIT;

PRAGMA foreign_keys=ON;

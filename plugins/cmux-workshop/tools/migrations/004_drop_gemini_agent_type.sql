-- Migration 004: remove Gemini from the agent CLI matrix.
--
-- Existing rows with type='gemini' are preserved by rewriting them to
-- type='codex'. SQLite cannot alter CHECK constraints in place, so agents is
-- rebuilt with the new type enum.

PRAGMA foreign_keys=OFF;

BEGIN;

DROP TABLE IF EXISTS agents_new;

CREATE TABLE agents_new (
    id             TEXT PRIMARY KEY,
    name           TEXT    NOT NULL,
    type           TEXT    NOT NULL CHECK (type IN ('claude', 'codex', 'custom')),
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

INSERT INTO agents_new (
    id,
    name,
    type,
    role,
    model,
    agent_file,
    source_type,
    source_origin,
    launch_command,
    cli_binary,
    is_caller,
    position
)
SELECT
    id,
    name,
    CASE WHEN type = 'gemini' THEN 'codex' ELSE type END AS type,
    role,
    model,
    agent_file,
    source_type,
    source_origin,
    launch_command,
    cli_binary,
    is_caller,
    position
  FROM agents;

DROP TABLE agents;
ALTER TABLE agents_new RENAME TO agents;

CREATE INDEX IF NOT EXISTS idx_agents_position ON agents(position);

UPDATE agents
   SET cli_binary = 'codex',
       launch_command = COALESCE(NULLIF(launch_command, 'gemini --yolo --model gemini-3.1-pro-preview'), 'codex --full-auto'),
       model = CASE WHEN model LIKE 'Gemini%' THEN 'GPT-5.x' ELSE model END
 WHERE type = 'codex'
   AND (cli_binary = 'gemini'
        OR launch_command LIKE 'gemini %'
        OR model LIKE 'Gemini%');

INSERT OR IGNORE INTO project (id, schema_version, name, description, created_at, updated_at)
VALUES (1, 4, '(uninitialized)', NULL, datetime('now'), datetime('now'));

UPDATE project SET schema_version = 4 WHERE id = 1;

COMMIT;

PRAGMA foreign_keys=ON;

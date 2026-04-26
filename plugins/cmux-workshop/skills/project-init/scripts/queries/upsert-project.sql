-- Upsert project row + PRD pointer + mark PRD progress complete.
-- Placeholders: {NAME} and {DESCRIPTION} must be SQL-escaped by caller
-- (use `tools/db.sh quote <val>` to produce safe literals including wrapping quotes).
-- Example (shell):
--   NAME=$(db.sh quote "my-project")
--   DESC=$(db.sh quote "A neat idea")
--   sed -e "s|{NAME}|$NAME|g" -e "s|{DESCRIPTION}|$DESC|g" upsert-project.sql \
--     | db.sh run /dev/stdin

INSERT OR REPLACE INTO project (id, schema_version, name, description, created_at, updated_at)
VALUES (1, 4,
        {NAME}, {DESCRIPTION},
        COALESCE((SELECT created_at FROM project WHERE id = 1 AND name <> '(uninitialized)'), datetime('now')),
        datetime('now'));

INSERT OR REPLACE INTO prd (id, path, created_at)
VALUES (1, '.claude/PRD.md',
        COALESCE((SELECT created_at FROM prd WHERE id = 1), datetime('now')));

UPDATE progress
   SET completed = 1,
       completed_at = datetime('now')
 WHERE phase = 'prd';

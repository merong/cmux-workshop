-- Reset mode 4: "PRD만 삭제".
-- Drops PRD pointer + progress.prd. Keeps agents + deployed state.

DELETE FROM prd;

UPDATE progress
   SET completed = 0, completed_at = NULL
 WHERE phase = 'prd';

UPDATE project SET updated_at = datetime('now') WHERE id = 1;

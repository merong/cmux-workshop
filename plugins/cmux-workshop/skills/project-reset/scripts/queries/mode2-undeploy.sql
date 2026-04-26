-- Reset mode 2: "cmux 배포만 해제".
-- Wipes local zone, rolls back deployed progress. Keeps PRD + agents intact.

DELETE FROM local_surfaces;
DELETE FROM local_workspace;
DELETE FROM local_kv;

UPDATE progress SET completed = 0, completed_at = NULL WHERE phase = 'deployed';
UPDATE project  SET updated_at = datetime('now') WHERE id = 1;

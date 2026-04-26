-- Reset mode 3: "에이전트 재설계".
-- Drops agents + layout + local zone. Keeps project + PRD + progress.prd.

DELETE FROM layout_splits;
DELETE FROM agents;

DELETE FROM local_surfaces;
DELETE FROM local_workspace;
DELETE FROM local_kv;

UPDATE progress
   SET completed = 0, completed_at = NULL
 WHERE phase IN ('agents', 'deployed');

UPDATE project SET updated_at = datetime('now') WHERE id = 1;

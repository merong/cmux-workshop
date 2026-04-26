-- Mark phase 3 complete + bump project.updated_at.
-- Run after all local_surfaces rows are in place and at least one agent is running.
UPDATE progress
   SET completed = 1,
       completed_at = datetime('now')
 WHERE phase = 'deployed';

UPDATE project
   SET updated_at = datetime('now')
 WHERE id = 1;

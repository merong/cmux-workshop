-- Mark phase 2 complete + bump project.updated_at. Must run after all agent
-- and split inserts are committed.
UPDATE progress
   SET completed = 1,
       completed_at = datetime('now')
 WHERE phase = 'agents';

UPDATE project
   SET updated_at = datetime('now')
 WHERE id = 1;

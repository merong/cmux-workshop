-- Wipe portable zone. Progress rows re-seeded to 0 afterwards.
DELETE FROM layout_splits;
DELETE FROM agents;
DELETE FROM prd;
DELETE FROM project;
UPDATE progress SET completed = 0, completed_at = NULL;
DELETE FROM metadata;

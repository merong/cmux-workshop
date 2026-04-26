-- Wipe machine-local zone. Called before re-deploying or when committing.
DELETE FROM local_surfaces;
DELETE FROM local_workspace;
DELETE FROM local_kv;

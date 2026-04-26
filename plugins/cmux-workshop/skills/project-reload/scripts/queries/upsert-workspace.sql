-- Upsert the single local_workspace row.
-- Placeholders:
--   {WORKSPACE_ID}  quoted cmux workspace ref (e.g. 'workspace:7')

INSERT INTO local_workspace (id, workspace_id, created_at, updated_at)
VALUES (1,
        {WORKSPACE_ID},
        COALESCE((SELECT created_at FROM local_workspace WHERE id = 1), datetime('now')),
        datetime('now'))
ON CONFLICT(id) DO UPDATE SET
    workspace_id = excluded.workspace_id,
    updated_at   = excluded.updated_at;

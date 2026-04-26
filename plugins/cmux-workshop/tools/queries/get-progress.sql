-- Return all three progress rows as JSON
-- Use with: db.sh json "$(cat tools/queries/get-progress.sql)"
SELECT phase, completed, completed_at FROM progress ORDER BY
    CASE phase WHEN 'prd' THEN 1 WHEN 'agents' THEN 2 WHEN 'deployed' THEN 3 END;

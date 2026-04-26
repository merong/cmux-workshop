-- Read current PRD progress + project info for existing-project branch.
-- Returns one row if project exists, nothing otherwise.
SELECT p.name           AS name,
       p.description    AS description,
       pr.path          AS prd_path,
       pg.completed     AS prd_completed,
       pg.completed_at  AS prd_completed_at,
       (SELECT completed FROM progress WHERE phase = 'agents')   AS agents_completed,
       (SELECT completed FROM progress WHERE phase = 'deployed') AS deployed_completed
FROM project p
LEFT JOIN prd pr      ON pr.id = 1
LEFT JOIN progress pg ON pg.phase = 'prd'
WHERE p.id = 1;

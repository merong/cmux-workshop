-- Current cmux runtime surfaces joined with agent metadata.
-- Missing surfaces (no local_surfaces row) are returned with NULLs.
SELECT a.id                AS agent_id,
       a.name              AS agent_name,
       a.is_caller         AS is_caller,
       s.surface_id        AS surface_id,
       s.pane_id           AS pane_id,
       s.tab_title         AS tab_title,
       s.status            AS status,
       s.cli_session_id    AS cli_session_id,
       s.cli_session_label AS cli_session_label,
       s.last_active_at    AS last_active_at,
       s.updated_at        AS surface_updated_at
FROM agents a
LEFT JOIN local_surfaces s ON s.agent_id = a.id
ORDER BY a.is_caller DESC, a.position ASC;

-- Return the singleton project_info row.
-- Empty result when no capture has run yet.
SELECT project_name,
       project_summary,
       project_root,
       cmux_workspace_id,
       cmux_workspace_title,
       cmux_socket_path,
       git_remote_url,
       git_branch,
       captured_at,
       created_at,
       updated_at
FROM project_info
WHERE id = 1;

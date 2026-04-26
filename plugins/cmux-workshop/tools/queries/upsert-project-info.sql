-- Upsert the singleton project_info row.
-- Placeholders (all SQL-quoted by caller via tools/db.sh quote, or bare NULL):
--   {PROJECT_NAME}         quoted
--   {PROJECT_SUMMARY}      quoted or NULL
--   {PROJECT_ROOT}         quoted (absolute path)
--   {CMUX_WORKSPACE_ID}    quoted or NULL
--   {CMUX_WORKSPACE_TITLE} quoted or NULL
--   {CMUX_SOCKET_PATH}     quoted or NULL
--   {GIT_REMOTE_URL}       quoted or NULL
--   {GIT_BRANCH}           quoted or NULL

INSERT INTO project_info (
    id,
    project_name, project_summary, project_root,
    cmux_workspace_id, cmux_workspace_title, cmux_socket_path,
    git_remote_url, git_branch,
    captured_at,
    created_at,
    updated_at
)
VALUES (
    1,
    {PROJECT_NAME}, {PROJECT_SUMMARY}, {PROJECT_ROOT},
    {CMUX_WORKSPACE_ID}, {CMUX_WORKSPACE_TITLE}, {CMUX_SOCKET_PATH},
    {GIT_REMOTE_URL}, {GIT_BRANCH},
    datetime('now'),
    COALESCE((SELECT created_at FROM project_info WHERE id = 1), datetime('now')),
    datetime('now')
)
ON CONFLICT(id) DO UPDATE SET
    project_name         = excluded.project_name,
    project_summary      = excluded.project_summary,
    project_root         = excluded.project_root,
    cmux_workspace_id    = excluded.cmux_workspace_id,
    cmux_workspace_title = excluded.cmux_workspace_title,
    cmux_socket_path     = excluded.cmux_socket_path,
    git_remote_url       = excluded.git_remote_url,
    git_branch           = excluded.git_branch,
    captured_at          = excluded.captured_at,
    updated_at           = excluded.updated_at;

-- Template for a single local_surfaces row.
-- Placeholders:
--   {AGENT_ID}    quoted, must exist in agents.id
--   {SURFACE_ID}  quoted or NULL
--   {PANE_ID}     quoted or NULL
--   {TAB_TITLE}   quoted
--   {STATUS}      quoted enum: 'running'|'stopped'|'skipped'|'error'
--   {SESSION_ID}  quoted VARCHAR(255) or NULL
--   {SESSION_LABEL} quoted VARCHAR(255) or NULL
--   {LAST_ACTIVE_AT} quoted VARCHAR(64), datetime('now'), or NULL

INSERT INTO local_surfaces (
    agent_id,
    surface_id,
    pane_id,
    tab_title,
    status,
    cli_session_id,
    cli_session_label,
    last_active_at,
    updated_at
)
VALUES (
    {AGENT_ID},
    {SURFACE_ID},
    {PANE_ID},
    {TAB_TITLE},
    {STATUS},
    {SESSION_ID},
    {SESSION_LABEL},
    {LAST_ACTIVE_AT},
    datetime('now')
);

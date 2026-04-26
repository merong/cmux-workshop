-- Template for a single agent insert. Placeholders are SQL-quoted by caller
-- via tools/db.sh quote. Leave numeric / keyword placeholders unquoted.
--
-- Required placeholders:
--   {ID}             quoted, e.g. 'implementer'
--   {NAME}           quoted
--   {TYPE}           quoted enum: 'claude'|'codex'|'gemini'|'custom'
--   {ROLE}           quoted or NULL
--   {MODEL}          quoted or NULL
--   {AGENT_FILE}     quoted path
--   {SOURCE_TYPE}    quoted enum: 'local-library'|'voltagent'|'custom'
--   {SOURCE_ORIGIN}  quoted or NULL
--   {LAUNCH_COMMAND} quoted or NULL (NULL for caller)
--   {CLI_BINARY}     quoted or NULL
--   {IS_CALLER}      bare 0 or 1
--   {POSITION}       bare integer (display order)

INSERT INTO agents
    (id, name, type, role, model, agent_file,
     source_type, source_origin,
     launch_command, cli_binary, is_caller, position)
VALUES
    ({ID}, {NAME}, {TYPE}, {ROLE}, {MODEL}, {AGENT_FILE},
     {SOURCE_TYPE}, {SOURCE_ORIGIN},
     {LAUNCH_COMMAND}, {CLI_BINARY}, {IS_CALLER}, {POSITION});

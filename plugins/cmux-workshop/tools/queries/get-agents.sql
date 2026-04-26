-- All agents ordered for display. Caller first.
SELECT id, name, type, role, model, agent_file,
       source_type, source_origin,
       launch_command, cli_binary, is_caller, position
FROM agents
ORDER BY is_caller DESC, position ASC;

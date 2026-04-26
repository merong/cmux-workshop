-- Layout splits in execution order
SELECT position, agent_id, direction, from_agent_id
FROM layout_splits
ORDER BY position ASC;

-- Template for a single layout_splits row.
--
-- Placeholders:
--   {POSITION}      bare integer, 0-based execution order
--   {AGENT_ID}      quoted, matches agents.id
--   {DIRECTION}     quoted enum: 'left'|'right'|'up'|'down'
--   {FROM_AGENT_ID} quoted, references agents.id (or 'claude' caller key)

INSERT INTO layout_splits (position, agent_id, direction, from_agent_id)
VALUES ({POSITION}, {AGENT_ID}, {DIRECTION}, {FROM_AGENT_ID});

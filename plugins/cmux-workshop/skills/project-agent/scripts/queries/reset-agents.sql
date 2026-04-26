-- Wipe agents + layout_splits before re-designing the team.
-- Run as: db.sh run reset-agents.sql
-- Does not touch progress/project/prd.
DELETE FROM layout_splits;
DELETE FROM agents;

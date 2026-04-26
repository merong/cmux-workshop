-- Roll back deployed progress when agents change after initial deploy.
-- Does not close cmux panes — project:reload is responsible for reconciling.
UPDATE progress
   SET completed = 0,
       completed_at = NULL
 WHERE phase = 'deployed';

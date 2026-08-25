-- Add the new table to the existing PowerSync publication so rows
-- sync down to devices like every other table.
alter publication powersync add table public.notification;

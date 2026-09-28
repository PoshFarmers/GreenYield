-- ============================================================
-- Fix: Publish recurring_schedule to PowerSync
-- ============================================================

-- The recurring_schedule table was created in 20260927093817 but missed from the powersync publication
alter publication powersync add table recurring_schedule;

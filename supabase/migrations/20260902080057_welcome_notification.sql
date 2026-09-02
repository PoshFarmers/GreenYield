-- ============================================================
-- GreenYield — welcome notification
-- Fires once, right after `CompleteProfileScreen` inserts a user's
-- `profile` row (their first real "session" in the app, since the row
-- doesn't exist before that point). Reuses send_notification() from
-- 20260829050340_notification_events.sql, so it shows up through the
-- exact same notification bell / list / unread-count plumbing as every
-- other notification — no client changes needed.
-- ============================================================

create or replace function notify_welcome_on_profile_created() returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform send_notification(
    new.id,
    'welcome',
    'Welcome to GreenYield! 🌱',
    'Glad to have you here. Tap Settings (top-right avatar) to set your '
    'language, theme, and notification preferences. Browse the Home tab '
    'to get started, and use Chat if you ever need a hand.',
    jsonb_build_object('screen', 'settings'),
    'profile',
    new.id
  );
  return new;
end;
$$;

create trigger trg_notify_welcome_on_profile_created
  after insert on profile
  for each row execute function notify_welcome_on_profile_created();

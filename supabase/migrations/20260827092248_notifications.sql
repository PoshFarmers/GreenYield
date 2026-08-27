-- ============================================================
-- GENERAL COMPONENT: 3.4 Notifications
-- Cross-cutting: not owned by any single main component.
-- ============================================================

create type notification_channel as enum ('in_app', 'push', 'sms', 'email');

create table notification (
  id           uuid primary key default gen_random_uuid(),
  profile_id   uuid not null references profile(id) on delete cascade,
  type         text not null,  -- e.g. 'order_status_changed','delivery_assigned','payment_received','price_alert','new_message'
  title        text not null,
  body         text,
  payload      jsonb not null default '{}',
  source_table text,           -- generic reference to originating record, e.g. 'orders'
  source_id    uuid,
  read_at      timestamptz,
  created_at   timestamptz not null default now()
);

create index idx_notification_profile_created on notification(profile_id, created_at desc);
create index idx_notification_profile_unread  on notification(profile_id) where read_at is null;

create table notification_preference (
  id                uuid primary key default gen_random_uuid(),
  profile_id        uuid not null references profile(id) on delete cascade,
  notification_type text not null,
  channel           notification_channel not null,
  enabled           boolean not null default true,
  created_at        timestamptz not null default now(),
  unique (profile_id, notification_type, channel)
);

alter table notification enable row level security;
alter table notification_preference enable row level security;

create policy "notification_select_own" on notification for select using (auth.uid() = profile_id);
create policy "notification_update_own" on notification for update using (auth.uid() = profile_id);

create policy "notification_preference_select_own" on notification_preference for select using (auth.uid() = profile_id);
create policy "notification_preference_insert_own" on notification_preference for insert with check (auth.uid() = profile_id);
create policy "notification_preference_update_own" on notification_preference for update using (auth.uid() = profile_id);
create policy "notification_preference_delete_own" on notification_preference for delete using (auth.uid() = profile_id);

-- `notification` rows are written by trusted backend code (Edge Functions using the
-- service role, which bypasses RLS) - no client-facing insert policy on purpose.

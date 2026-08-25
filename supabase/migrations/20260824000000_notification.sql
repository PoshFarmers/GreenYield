-- ============================================================
-- GreenYield — generic notification system
-- One table, usable by any feature: a farmer listing a crop, a buyer
-- placing an order, a driver being assigned a route, etc. all just
-- insert a row here. `type` + `data` keep it open for extension
-- without further schema changes (Open/Closed).
-- ============================================================

create table notification (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  title       text not null,
  body        text not null,
  type        text not null default 'general',   -- free-form: 'order', 'crop', 'system', ...
  data        jsonb not null default '{}'::jsonb, -- extra payload, e.g. {"order_id": "..."}
  is_read     boolean not null default false,
  created_at  timestamptz not null default now()
);

create index idx_notification_user_created
  on notification (user_id, created_at desc);

alter table notification enable row level security;

-- Every signed-in user can only ever see/manage their own notifications.
create policy "notification_select_own" on notification
  for select using (auth.uid() = user_id);

create policy "notification_update_own" on notification
  for update using (auth.uid() = user_id);

-- Any authenticated user can create a notification *for another user*
-- (e.g. a buyer notifying a farmer about an order). This is
-- intentionally permissive for a basic system — if abuse becomes a
-- concern later, move notification creation behind a security-definer
-- function or an edge function instead of a direct table insert.
create policy "notification_insert_authenticated" on notification
  for insert with check (auth.role() = 'authenticated');

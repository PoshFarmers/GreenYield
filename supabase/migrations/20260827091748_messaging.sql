-- ============================================================
-- GENERAL COMPONENT: 3.3 Communication / Messagin

-- ============================================================

create type conversation_context as enum ('order', 'journey', 'general');

create table conversation (
  id           uuid primary key default gen_random_uuid(),
  context_type conversation_context not null default 'general',
  order_id     uuid,   -- soft ref -> orders(id)  [Component 2]
  journey_id   uuid,   -- soft ref -> journey(id) [Component 3]
  title        text,
  created_at   timestamptz not null default now()
);

create index idx_conversation_order   on conversation(order_id) where order_id is not null;
create index idx_conversation_journey on conversation(journey_id) where journey_id is not null;

create table conversation_participant (
  id              uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references conversation(id) on delete cascade,
  profile_id      uuid not null references profile(id) on delete cascade,
  joined_at       timestamptz not null default now(),
  last_read_at    timestamptz,
  unique (conversation_id, profile_id)
);

create index idx_conversation_participant_profile on conversation_participant(profile_id);

create table message (
  id              uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references conversation(id) on delete cascade,
  sender_id       uuid not null references profile(id),
  body            text,
  attachment_url  text,
  created_at      timestamptz not null default now()
);

create index idx_message_conversation_created on message(conversation_id, created_at);

alter table conversation enable row level security;
alter table conversation_participant enable row level security;
alter table message enable row level security;

create or replace function is_conversation_participant(p_conversation_id uuid)
returns boolean as $$
  select exists (
    select 1 from conversation_participant
    where conversation_id = p_conversation_id and profile_id = auth.uid()
  );
$$ language sql stable security definer;

create policy "conversation_select_participant" on conversation
  for select using (is_conversation_participant(id));
create policy "conversation_insert_authenticated" on conversation
  for insert with check (auth.uid() is not null);

create policy "conversation_participant_select_own" on conversation_participant
  for select using (is_conversation_participant(conversation_id));
create policy "conversation_participant_insert_self_or_participant" on conversation_participant
  for insert with check (profile_id = auth.uid() or is_conversation_participant(conversation_id));
create policy "conversation_participant_update_own" on conversation_participant
  for update using (profile_id = auth.uid());

create policy "message_select_participant" on message
  for select using (is_conversation_participant(conversation_id));
create policy "message_insert_participant" on message
  for insert with check (sender_id = auth.uid() and is_conversation_participant(conversation_id));

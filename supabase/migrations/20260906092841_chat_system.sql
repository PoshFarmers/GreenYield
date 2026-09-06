-- ============================================================
-- GreenYield — Epic 4 / Task 4.1: Direct Messaging System
-- (Buyer <-> Farmer, Buyer <-> Driver, Farmer <-> Driver)
--
-- Extends the existing `conversation` / `conversation_participant` /
-- `message` schema from 20260827091748_messaging.sql rather than
-- introducing a parallel set of tables. Those tables are still empty
-- and unreferenced by any Dart code, so there's nothing to migrate
-- and no naming conflict to work around — this is purely additive:
-- new columns, new indexes, one trigger, and the RPCs the direct-
-- Supabase (no PowerSync) messaging feature needs on top of them.
--
-- The original schema was already built with reads in mind: it's
-- context-agnostic ('general' | 'order' | 'journey'), N-participant
-- rather than hard-coded to a pair of roles, and — per
-- 20260830121221's comment — already snapshots each participant's own
-- display_name/avatar_url onto their own row rather than relying on a
-- live join, since RLS on `profile` only allows reading your own row.
-- We keep that same snapshot pattern for the new `role` column below,
-- and reuse `last_read_at` as the unread cursor instead of adding a
-- per-message `is_read` flag — it's the natural fit for the table
-- that's already there, and it makes "seen" a single timestamp
-- comparison instead of a write-per-message-per-recipient.
-- ============================================================

-- ---------------------------------------------------------------
-- message: needs to distinguish an image attachment from a future
-- attachment type, and a place to bump `conversation.updated_at`.
-- ---------------------------------------------------------------
alter table message
  add column attachment_type text; -- e.g. 'image'; null when body-only

alter table conversation
  add column updated_at timestamptz not null default now();

create index idx_message_unread_lookup on message(conversation_id, sender_id, created_at);

-- Keep conversation.updated_at current so "most recent thread first"
-- sorting on the Chat tab doesn't require a join against `message` on
-- every list render.
create or replace function touch_conversation_on_message()
returns trigger
language plpgsql
as $$
begin
  update conversation set updated_at = now() where id = new.conversation_id;
  return new;
end;
$$;

create trigger trg_touch_conversation_on_message
  after insert on message
  for each row execute function touch_conversation_on_message();

-- ---------------------------------------------------------------
-- conversation_participant: snapshot each participant's own role
-- ('buyer' | 'farmer' | 'driver') in *this* conversation, the same
-- way display_name/avatar_url are already snapshotted. A profile can
-- hold more than one role overall, so the role that mattered for a
-- given thread has to be recorded per-thread rather than looked up
-- fresh from `profile_role` later.
-- ---------------------------------------------------------------
alter table conversation_participant
  add column role text check (role in ('buyer', 'farmer', 'driver'));

-- ---------------------------------------------------------------
-- get_or_create_conversation: atomically returns the existing direct
-- (context_type = 'general', no order/journey) thread between the
-- caller and another participant, or creates one — inserting both
-- `conversation_participant` rows (with their display_name/avatar_url/
-- role snapshots) in the same transaction, since this is a direct
-- message the other side hasn't "joined" yet.
--
-- The caller's own role and the other participant's role are passed
-- explicitly — each entry point already knows both (e.g. "Message
-- Farmer" only ever shows up for a buyer looking at a specific
-- farmer). Being security definer, this can also read the other
-- user's `profile` / `profile_role` rows to snapshot them, which the
-- caller's own RLS wouldn't allow directly.
--
-- Race-safety: an advisory lock keyed to the sorted participant pair
-- is held for the transaction so two concurrent "get or create" calls
-- for the same pair can't both insert.
-- ---------------------------------------------------------------
create or replace function get_or_create_conversation(
  p_caller_role text,
  p_other_user_id uuid,
  p_other_role text
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller_id uuid := auth.uid();
  v_conversation_id uuid;
  v_lock_key bigint;
  v_caller_name text;
  v_caller_avatar text;
  v_other_name text;
  v_other_avatar text;
begin
  if v_caller_id is null then
    raise exception 'not authenticated';
  end if;

  if p_caller_role not in ('buyer', 'farmer', 'driver')
     or p_other_role not in ('buyer', 'farmer', 'driver') then
    raise exception 'invalid role: % / %', p_caller_role, p_other_role;
  end if;

  if p_caller_role = p_other_role then
    raise exception 'caller and other participant must have different roles';
  end if;

  if p_other_user_id = v_caller_id then
    raise exception 'cannot start a conversation with yourself';
  end if;

  if not exists (
    select 1 from profile_role
    where profile_id = v_caller_id and role = p_caller_role::user_role
  ) then
    raise exception 'caller does not hold role %', p_caller_role;
  end if;

  if not exists (
    select 1 from profile_role
    where profile_id = p_other_user_id and role = p_other_role::user_role
  ) then
    raise exception 'other participant does not hold role %', p_other_role;
  end if;

  -- Serialize concurrent creates for this exact pair.
  v_lock_key := hashtextextended(
    concat_ws(
      ':',
      (select least(v_caller_id, p_other_user_id)::text),
      (select greatest(v_caller_id, p_other_user_id)::text)
    ),
    0
  );
  perform pg_advisory_xact_lock(v_lock_key);

  select cp1.conversation_id into v_conversation_id
  from conversation_participant cp1
  join conversation_participant cp2
    on cp2.conversation_id = cp1.conversation_id and cp2.profile_id = p_other_user_id
  join conversation c on c.id = cp1.conversation_id
  where cp1.profile_id = v_caller_id
    and c.context_type = 'general'
    and c.order_id is null
    and c.journey_id is null
    and (
      select count(*) from conversation_participant cp3
      where cp3.conversation_id = cp1.conversation_id
    ) = 2
  limit 1;

  if v_conversation_id is not null then
    return v_conversation_id;
  end if;

  select trim(concat_ws(' ', first_name, last_name)), avatar_url
    into v_caller_name, v_caller_avatar
    from profile where id = v_caller_id;

  select trim(concat_ws(' ', first_name, last_name)), avatar_url
    into v_other_name, v_other_avatar
    from profile where id = p_other_user_id;

  insert into conversation (context_type)
  values ('general')
  returning id into v_conversation_id;

  insert into conversation_participant
    (conversation_id, profile_id, role, display_name, avatar_url)
  values
    (v_conversation_id, v_caller_id, p_caller_role, v_caller_name, v_caller_avatar),
    (v_conversation_id, p_other_user_id, p_other_role, v_other_name, v_other_avatar);

  return v_conversation_id;
end;
$$;

grant execute on function get_or_create_conversation(text, uuid, text) to authenticated;

-- ---------------------------------------------------------------
-- unread_conversation_count: distinct THREADS with at least one
-- message from someone else created after the caller's
-- `last_read_at` cursor for that thread — backs the yellow nav badge.
-- ---------------------------------------------------------------
create or replace function unread_conversation_count()
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::int
  from conversation_participant cp
  where cp.profile_id = auth.uid()
    and exists (
      select 1 from message m
      where m.conversation_id = cp.conversation_id
        and m.sender_id <> auth.uid()
        and m.created_at > coalesce(cp.last_read_at, 'epoch'::timestamptz)
    );
$$;

grant execute on function unread_conversation_count() to authenticated;

-- ---------------------------------------------------------------
-- get_chat_threads: one row per direct conversation the caller is in,
-- reading the OTHER participant's snapshot (display_name/avatar_url/
-- role) straight off their `conversation_participant` row rather than
-- joining `profile` — same reasoning as 20260830121221's snapshot
-- columns: no separate RLS-safe read path is needed this way, and it
-- stays consistent with how those columns already work for anything
-- else that reads this schema later.
-- ---------------------------------------------------------------
create or replace function get_chat_threads()
returns table (
  conversation_id   uuid,
  other_user_id     uuid,
  other_role        text,
  other_name        text,
  other_avatar_url  text,
  last_message_text text,
  last_message_at   timestamptz,
  is_last_from_me   boolean,
  has_unread        boolean,
  updated_at        timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    c.id as conversation_id,
    other.profile_id as other_user_id,
    other.role as other_role,
    coalesce(nullif(trim(other.display_name), ''), 'Unknown') as other_name,
    other.avatar_url as other_avatar_url,
    lm.body as last_message_text,
    lm.created_at as last_message_at,
    (lm.sender_id = auth.uid()) as is_last_from_me,
    exists (
      select 1 from message um
      where um.conversation_id = c.id
        and um.sender_id <> auth.uid()
        and um.created_at > coalesce(me.last_read_at, 'epoch'::timestamptz)
    ) as has_unread,
    c.updated_at
  from conversation c
  join conversation_participant me
    on me.conversation_id = c.id and me.profile_id = auth.uid()
  join conversation_participant other
    on other.conversation_id = c.id and other.profile_id <> auth.uid()
  left join lateral (
    select m.body, m.attachment_type, m.created_at, m.sender_id
    from message m
    where m.conversation_id = c.id
    order by m.created_at desc
    limit 1
  ) lm on true
  where c.context_type = 'general'
    and c.order_id is null
    and c.journey_id is null
  order by c.updated_at desc;
$$;

grant execute on function get_chat_threads() to authenticated;

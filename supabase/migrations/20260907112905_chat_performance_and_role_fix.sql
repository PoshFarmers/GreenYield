-- ============================================================
-- GreenYield - Chat performance + active-role correctness
--
-- Fixes:
--   1. Thread queries are scoped to the user's ACTIVE role.
--   2. Existing get_or_create_conversation() must match roles as
--      well as user ids, otherwise multi-role users can reuse the
--      wrong conversation.
--   3. Adds indexes for the thread/unread queries.
--   4. Keeps the thread list query server-side but avoids unnecessary
--      duplicate work.
--   5. Backfills participant role snapshots when a profile has exactly
--      one role (legacy conversations created before role snapshots).
-- ============================================================

-- ------------------------------------------------------------
-- Helpful indexes
-- ------------------------------------------------------------
create index if not exists idx_conversation_participant_profile_role_conversation
  on conversation_participant(profile_id, role, conversation_id);

create index if not exists idx_message_conversation_created_sender
  on message(conversation_id, created_at desc, sender_id);

-- Legacy participant rows may have a null role. If the profile has exactly
-- one role, it is safe to restore that snapshot automatically.
update conversation_participant cp
set role = pr.role::text
from profile_role pr
where cp.role is null
  and cp.profile_id = pr.profile_id
  and (
    select count(*)
    from profile_role pr2
    where pr2.profile_id = cp.profile_id
  ) = 1;

-- ------------------------------------------------------------
-- Role-aware get_or_create_conversation()
-- ------------------------------------------------------------
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
    select 1
    from profile_role
    where profile_id = v_caller_id
      and role = p_caller_role::user_role
  ) then
    raise exception 'caller does not hold role %', p_caller_role;
  end if;

  if not exists (
    select 1
    from profile_role
    where profile_id = p_other_user_id
      and role = p_other_role::user_role
  ) then
    raise exception 'other participant does not hold role %', p_other_role;
  end if;

  -- Serialize concurrent creates for the same two users.
  v_lock_key := hashtextextended(
    concat_ws(
      ':',
      least(v_caller_id, p_other_user_id)::text,
      greatest(v_caller_id, p_other_user_id)::text
    ),
    0
  );
  perform pg_advisory_xact_lock(v_lock_key);

  -- IMPORTANT: roles are part of the identity of a direct thread.
  -- A user may hold multiple roles, so matching only profile_id can
  -- incorrectly reuse a Buyer/Farmer chat while acting as Driver.
  select cp1.conversation_id
  into v_conversation_id
  from conversation_participant cp1
  join conversation_participant cp2
    on cp2.conversation_id = cp1.conversation_id
   and cp2.profile_id = p_other_user_id
   and cp2.role = p_other_role
  join conversation c
    on c.id = cp1.conversation_id
  where cp1.profile_id = v_caller_id
    and cp1.role = p_caller_role
    and c.context_type = 'general'
    and c.order_id is null
    and c.journey_id is null
    and (
      select count(*)
      from conversation_participant cp3
      where cp3.conversation_id = cp1.conversation_id
    ) = 2
  limit 1;

  if v_conversation_id is not null then
    return v_conversation_id;
  end if;

  select trim(concat_ws(' ', first_name, last_name)), avatar_url
  into v_caller_name, v_caller_avatar
  from profile
  where id = v_caller_id;

  select trim(concat_ws(' ', first_name, last_name)), avatar_url
  into v_other_name, v_other_avatar
  from profile
  where id = p_other_user_id;

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

-- ------------------------------------------------------------
-- Role-aware unread thread count
-- ------------------------------------------------------------
drop function if exists unread_conversation_count();

create or replace function unread_conversation_count(
  p_active_role text
) returns integer
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::int
  from conversation_participant cp
  where cp.profile_id = auth.uid()
    and cp.role = p_active_role
    and exists (
      select 1
      from message m
      where m.conversation_id = cp.conversation_id
        and m.sender_id <> auth.uid()
        and m.created_at > coalesce(cp.last_read_at, 'epoch'::timestamptz)
    );
$$;

grant execute on function unread_conversation_count(text) to authenticated;

-- ------------------------------------------------------------
-- Role-aware thread list
-- ------------------------------------------------------------
drop function if exists get_chat_threads();

create or replace function get_chat_threads(
  p_active_role text
)
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
  unread_count      int,
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
    coalesce(lm.sender_id = auth.uid(), false) as is_last_from_me,
    coalesce(unread.unread_count, 0) > 0 as has_unread,
    coalesce(unread.unread_count, 0)::int as unread_count,
    c.updated_at
  from conversation c
  join conversation_participant me
    on me.conversation_id = c.id
   and me.profile_id = auth.uid()
   and me.role = p_active_role
  join conversation_participant other
    on other.conversation_id = c.id
   and other.profile_id <> auth.uid()
  left join lateral (
    select m.body, m.created_at, m.sender_id
    from message m
    where m.conversation_id = c.id
    order by m.created_at desc
    limit 1
  ) lm on true
  left join lateral (
    select count(*)::int as unread_count
    from message um
    where um.conversation_id = c.id
      and um.sender_id <> auth.uid()
      and um.created_at > coalesce(me.last_read_at, 'epoch'::timestamptz)
  ) unread on true
  where c.context_type = 'general'
    and c.order_id is null
    and c.journey_id is null
  order by c.updated_at desc;
$$;

grant execute on function get_chat_threads(text) to authenticated;

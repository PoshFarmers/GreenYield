-- ============================================================
-- Adds unread_count to get_chat_threads() so the thread list
-- can display a per-thread unread message count badge.
--
-- The chat_system migration (20260906000000) already defined
-- get_chat_threads() returning has_unread (bool). We replace it
-- here to also return unread_count (int) — a count of messages
-- from the other participant that arrived after the caller's
-- last_read_at cursor for that thread.
-- ============================================================

drop function if exists get_chat_threads();

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
    (lm.sender_id = auth.uid()) as is_last_from_me,
    exists (
      select 1 from message um
      where um.conversation_id = c.id
        and um.sender_id <> auth.uid()
        and um.created_at > coalesce(me.last_read_at, 'epoch'::timestamptz)
    ) as has_unread,
    (
      select count(*)::int from message um
      where um.conversation_id = c.id
        and um.sender_id <> auth.uid()
        and um.created_at > coalesce(me.last_read_at, 'epoch'::timestamptz)
    ) as unread_count,
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
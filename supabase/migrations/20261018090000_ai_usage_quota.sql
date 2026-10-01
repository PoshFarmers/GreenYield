-- ============================================================
-- Quota guard for AI features (Gemini free tier).
--
-- Every AI request is "claimed" here first by the Edge Function (service
-- role), which enforces a per-user cooldown and a per-user daily cap
-- atomically. Server-only: no RLS policies, not in the PowerSync
-- publication, never read by the client.
-- ============================================================

create table if not exists ai_usage (
  id          bigserial primary key,
  user_id     uuid not null references auth.users (id) on delete cascade,
  feature     text not null,
  created_at  timestamptz not null default now()
);

create index if not exists idx_ai_usage_user_feature_time
  on ai_usage (user_id, feature, created_at desc);

alter table ai_usage enable row level security;
-- (No policies on purpose: only the service role touches this table.)

-- Returns 'ok' (and records the request), 'cooldown' or 'daily_cap'.
-- "Daily" is the Asia/Colombo calendar day.
create or replace function claim_ai_request(
  p_user_id          uuid,
  p_feature          text,
  p_cooldown_seconds integer,
  p_daily_cap        integer
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_last  timestamptz;
  v_today integer;
begin
  -- Serialise concurrent claims for the same user + feature.
  perform pg_advisory_xact_lock(hashtext(p_user_id::text || ':' || p_feature));

  select max(created_at) into v_last
  from ai_usage
  where user_id = p_user_id and feature = p_feature;

  if v_last is not null
     and v_last > now() - make_interval(secs => p_cooldown_seconds) then
    return 'cooldown';
  end if;

  select count(*) into v_today
  from ai_usage
  where user_id = p_user_id
    and feature = p_feature
    and (created_at at time zone 'Asia/Colombo')::date
        = (now() at time zone 'Asia/Colombo')::date;

  if v_today >= p_daily_cap then
    return 'daily_cap';
  end if;

  insert into ai_usage (user_id, feature) values (p_user_id, p_feature);
  return 'ok';
end;
$$;

revoke all on function claim_ai_request(uuid, text, integer, integer)
  from public, anon, authenticated;
grant execute on function claim_ai_request(uuid, text, integer, integer)
  to service_role;

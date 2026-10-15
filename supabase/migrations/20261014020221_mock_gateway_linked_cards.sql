-- ============================================================
-- MOCK ONLY: everything named mockgw_* and the linked_card.test_scenario
-- column exist to simulate a payment gateway. Drop them when swapping to a
-- real gateway (e.g. PayHere), which must tokenize on the client so the
-- PAN never reaches our backend.
--
-- Security model:
--   * PAN and CVC are validated inside mockgw_tokenize_card and NEVER stored.
--   * linked_card.gateway_token and test_scenario are not readable by clients
--     (column-level grants below).
--   * mockgw_* are internal: callable only by other SECURITY DEFINER
--     functions and service_role.
--   * Supabase default privileges grant EXECUTE to anon/authenticated on new
--     functions, so every revoke below names those roles explicitly.
-- ============================================================

-- ------------------------------------------------------------
-- Tables
-- ------------------------------------------------------------
create table linked_card (
  id             uuid primary key default gen_random_uuid(),
  profile_id     uuid not null references profile(id) on delete cascade,
  gateway_token  text not null unique,
  brand          text not null check (brand in ('visa', 'mastercard', 'amex', 'discover', 'other')),
  last4          text not null check (last4 ~ '^[0-9]{4}$'),
  exp_month      smallint not null check (exp_month between 1 and 12),
  exp_year       smallint not null check (exp_year >= 2000),
  holder_name    text not null,
  nickname       text,
  is_default     boolean not null default false,
  is_saved       boolean not null default true,  -- false = one-off card used at checkout, hidden from the list
  deleted_at     timestamptz,                    -- soft delete: token is kept so refunds to the card still work
  test_scenario  text not null default 'ok'      -- MOCK ONLY: drop when swapping to a real gateway
    check (test_scenario in ('ok', 'declined', 'insufficient_funds', 'expired_card', 'incorrect_cvc', 'payout_fails')),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  check (not is_default or is_saved)
);

create unique index uq_linked_card_one_default
  on linked_card(profile_id) where is_default and deleted_at is null;
create index idx_linked_card_profile
  on linked_card(profile_id) where deleted_at is null;

create trigger trg_linked_card_updated_at
  before update on linked_card for each row execute function set_updated_at();

create table gateway_transaction (
  id                uuid primary key default gen_random_uuid(),
  profile_id        uuid not null references profile(id) on delete cascade,
  linked_card_id    uuid references linked_card(id) on delete set null,
  kind              text not null check (kind in ('charge', 'payout', 'refund')),
  amount            numeric not null check (amount > 0),
  currency          text not null default 'LKR',
  status            text not null check (status in ('succeeded', 'failed')),
  failure_code      text,
  failure_message   text,
  gateway_reference text not null,               -- 'MOCK-...'
  purpose           text,                        -- e.g. 'wallet_topup', 'checkout', 'withdrawal'
  purpose_ref       uuid,
  request_id        uuid,                        -- client idempotency key, scoped per profile
  created_at        timestamptz not null default now()
);

create unique index uq_gateway_transaction_request
  on gateway_transaction(profile_id, request_id) where request_id is not null;
create index idx_gateway_transaction_profile
  on gateway_transaction(profile_id, created_at desc);

-- ------------------------------------------------------------
-- RLS and privileges
-- ------------------------------------------------------------
alter table linked_card enable row level security;
alter table gateway_transaction enable row level security;

create policy "linked_card_select_own" on linked_card
  for select using (auth.uid() = profile_id);
create policy "gateway_transaction_select_own" on gateway_transaction
  for select using (auth.uid() = profile_id);
-- No insert/update/delete policies: all writes go through the functions below.

revoke all on linked_card from anon, authenticated;
grant select (id, profile_id, brand, last4, exp_month, exp_year, holder_name,
              nickname, is_default, is_saved, deleted_at, created_at, updated_at)
  on linked_card to authenticated;

revoke all on gateway_transaction from anon, authenticated;
grant select on gateway_transaction to authenticated;

-- ------------------------------------------------------------
-- MOCK GATEWAY internals (not callable by clients)
-- ------------------------------------------------------------
create or replace function mockgw_luhn_valid(p_number text)
returns boolean
language plpgsql
immutable
as $$
declare
  v_sum   int := 0;
  v_digit int;
  v_alt   boolean := false;
  i       int;
begin
  if p_number is null or p_number !~ '^[0-9]+$' then
    return false;
  end if;
  for i in reverse length(p_number)..1 loop
    v_digit := substr(p_number, i, 1)::int;
    if v_alt then
      v_digit := v_digit * 2;
      if v_digit > 9 then v_digit := v_digit - 9; end if;
    end if;
    v_sum := v_sum + v_digit;
    v_alt := not v_alt;
  end loop;
  return v_sum % 10 = 0;
end;
$$;

create or replace function mockgw_card_brand(p_number text)
returns text
language plpgsql
immutable
as $$
begin
  if p_number ~ '^4' then
    return 'visa';
  elsif p_number ~ '^5[1-5]'
        or (length(p_number) >= 4 and left(p_number, 4)::int between 2221 and 2720) then
    return 'mastercard';
  elsif p_number ~ '^3[47]' then
    return 'amex';
  elsif p_number ~ '^(6011|65)' then
    return 'discover';
  end if;
  return 'other';
end;
$$;

create or replace function mockgw_card_expired(p_month integer, p_year integer)
returns boolean
language sql
stable
as $$
  select (make_date(p_year, p_month, 1) + interval '1 month')::date
         <= (now() at time zone 'Asia/Colombo')::date;
$$;

-- Validates the card and returns {token, brand, last4, scenario}.
-- Never stores or logs the PAN/CVC.
create or replace function mockgw_tokenize_card(
  p_number     text,
  p_exp_month  integer,
  p_exp_year   integer,
  p_cvc        text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_number   text := regexp_replace(coalesce(p_number, ''), '[ -]', '', 'g');
  v_brand    text;
  v_scenario text;
  v_this_year int := extract(year from (now() at time zone 'Asia/Colombo'))::int;
begin
  if v_number !~ '^[0-9]{13,19}$' or not mockgw_luhn_valid(v_number) then
    raise exception 'invalid_card_number' using errcode = '22023';
  end if;

  v_brand := mockgw_card_brand(v_number);
  if v_brand = 'amex' and length(v_number) <> 15 then
    raise exception 'invalid_card_number' using errcode = '22023';
  end if;

  if p_exp_month is null or p_exp_month not between 1 and 12
     or p_exp_year is null or p_exp_year < 2000 or p_exp_year > v_this_year + 20 then
    raise exception 'invalid_expiry' using errcode = '22023';
  end if;
  if mockgw_card_expired(p_exp_month, p_exp_year) then
    raise exception 'card_expired' using errcode = '22023';
  end if;

  if p_cvc is null or p_cvc !~ '^[0-9]{3,4}$' then
    raise exception 'invalid_cvc' using errcode = '22023';
  end if;

  v_scenario := case v_number
    when '4000000000000002' then 'declined'
    when '4000000000009995' then 'insufficient_funds'
    when '4000000000000069' then 'expired_card'
    when '4000000000000127' then 'incorrect_cvc'
    when '4000000000000341' then 'payout_fails'
    else 'ok'
  end;

  return jsonb_build_object(
    'token',    'tok_mock_' || replace(gen_random_uuid()::text, '-', ''),
    'brand',    v_brand,
    'last4',    right(v_number, 4),
    'scenario', v_scenario
  );
end;
$$;

-- Returns the stored row for an already-seen (profile, request_id), or a row
-- of NULLs (check .id) when none exists.
create or replace function mockgw_replay(p_profile_id uuid, p_request_id uuid)
returns gateway_transaction
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row gateway_transaction;
begin
  if p_request_id is not null then
    select * into v_row
    from gateway_transaction
    where profile_id = p_profile_id and request_id = p_request_id;
  end if;
  return v_row;
end;
$$;

create or replace function mockgw_record(
  p_profile_id  uuid,
  p_card_id     uuid,
  p_kind        text,
  p_amount      numeric,
  p_status      text,
  p_code        text,
  p_message     text,
  p_purpose     text,
  p_purpose_ref uuid,
  p_request_id  uuid
)
returns gateway_transaction
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row gateway_transaction;
begin
  insert into gateway_transaction (
    profile_id, linked_card_id, kind, amount, status,
    failure_code, failure_message, gateway_reference,
    purpose, purpose_ref, request_id
  ) values (
    p_profile_id, p_card_id, p_kind, p_amount, p_status,
    p_code, p_message,
    'MOCK-' || case p_kind when 'charge' then 'CH' when 'payout' then 'PO' else 'RF' end
      || '-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10)),
    p_purpose, p_purpose_ref, p_request_id
  )
  returning * into v_row;
  return v_row;
end;
$$;

-- Charge a card. Declines are returned as a 'failed' row, not raised, so the
-- attempt persists. Idempotent per (profile, request_id).
create or replace function mockgw_charge(
  p_profile_id     uuid,
  p_linked_card_id uuid,
  p_amount         numeric,
  p_purpose        text default null,
  p_purpose_ref    uuid default null,
  p_request_id     uuid default null
)
returns gateway_transaction
language plpgsql
security definer
set search_path = public
as $$
declare
  v_card linked_card;
  v_row  gateway_transaction;
  v_code text;
  v_msg  text;
begin
  if p_amount is null or p_amount <= 0 then
    raise exception 'invalid_amount' using errcode = '22023';
  end if;

  v_row := mockgw_replay(p_profile_id, p_request_id);
  if v_row.id is not null then
    return v_row;
  end if;

  select * into v_card
  from linked_card
  where id = p_linked_card_id and profile_id = p_profile_id and deleted_at is null;
  if v_card.id is null then
    raise exception 'card_not_found' using errcode = 'P0002';
  end if;

  v_code := case v_card.test_scenario
    when 'declined'           then 'card_declined'
    when 'insufficient_funds' then 'insufficient_funds'
    when 'expired_card'       then 'expired_card'
    when 'incorrect_cvc'      then 'incorrect_cvc'
    else null
  end;
  if v_code is null and mockgw_card_expired(v_card.exp_month, v_card.exp_year) then
    v_code := 'expired_card';
  end if;

  v_msg := case v_code
    when 'card_declined'       then 'Your card was declined.'
    when 'insufficient_funds'  then 'Your card has insufficient funds.'
    when 'expired_card'        then 'Your card has expired.'
    when 'incorrect_cvc'       then 'Your card''s security code is incorrect.'
    else null
  end;

  begin
    v_row := mockgw_record(
      p_profile_id, v_card.id, 'charge', p_amount,
      case when v_code is null then 'succeeded' else 'failed' end,
      v_code, v_msg, p_purpose, p_purpose_ref, p_request_id
    );
  exception when unique_violation then
    v_row := mockgw_replay(p_profile_id, p_request_id);
  end;
  return v_row;
end;
$$;

-- Pay out to a card (withdrawals). Only the 'payout_fails' test card fails.
create or replace function mockgw_payout(
  p_profile_id     uuid,
  p_linked_card_id uuid,
  p_amount         numeric,
  p_purpose        text default null,
  p_purpose_ref    uuid default null,
  p_request_id     uuid default null
)
returns gateway_transaction
language plpgsql
security definer
set search_path = public
as $$
declare
  v_card linked_card;
  v_row  gateway_transaction;
  v_code text;
  v_msg  text;
begin
  if p_amount is null or p_amount <= 0 then
    raise exception 'invalid_amount' using errcode = '22023';
  end if;

  v_row := mockgw_replay(p_profile_id, p_request_id);
  if v_row.id is not null then
    return v_row;
  end if;

  select * into v_card
  from linked_card
  where id = p_linked_card_id and profile_id = p_profile_id and deleted_at is null;
  if v_card.id is null then
    raise exception 'card_not_found' using errcode = 'P0002';
  end if;

  if v_card.test_scenario = 'payout_fails' then
    v_code := 'payout_failed';
    v_msg  := 'The payout to this card could not be completed.';
  elsif mockgw_card_expired(v_card.exp_month, v_card.exp_year) then
    v_code := 'expired_card';
    v_msg  := 'Your card has expired.';
  end if;

  begin
    v_row := mockgw_record(
      p_profile_id, v_card.id, 'payout', p_amount,
      case when v_code is null then 'succeeded' else 'failed' end,
      v_code, v_msg, p_purpose, p_purpose_ref, p_request_id
    );
  exception when unique_violation then
    v_row := mockgw_replay(p_profile_id, p_request_id);
  end;
  return v_row;
end;
$$;

-- Refund to a card. Always succeeds, and works for soft-deleted cards
-- (the token is kept for exactly this reason).
create or replace function mockgw_refund(
  p_profile_id     uuid,
  p_linked_card_id uuid,
  p_amount         numeric,
  p_purpose        text default null,
  p_purpose_ref    uuid default null,
  p_request_id     uuid default null
)
returns gateway_transaction
language plpgsql
security definer
set search_path = public
as $$
declare
  v_card linked_card;
  v_row  gateway_transaction;
begin
  if p_amount is null or p_amount <= 0 then
    raise exception 'invalid_amount' using errcode = '22023';
  end if;

  v_row := mockgw_replay(p_profile_id, p_request_id);
  if v_row.id is not null then
    return v_row;
  end if;

  select * into v_card
  from linked_card
  where id = p_linked_card_id and profile_id = p_profile_id;
  if v_card.id is null then
    raise exception 'card_not_found' using errcode = 'P0002';
  end if;

  begin
    v_row := mockgw_record(
      p_profile_id, v_card.id, 'refund', p_amount, 'succeeded',
      null, null, p_purpose, p_purpose_ref, p_request_id
    );
  exception when unique_violation then
    v_row := mockgw_replay(p_profile_id, p_request_id);
  end;
  return v_row;
end;
$$;

-- ------------------------------------------------------------
-- Client RPCs
-- ------------------------------------------------------------
create or replace function add_linked_card(
  p_number        text,
  p_exp_month     integer,
  p_exp_year      integer,
  p_cvc           text,
  p_holder_name   text,
  p_nickname      text default null,
  p_make_default  boolean default false,
  p_save          boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid         uuid := auth.uid();
  v_holder      text := btrim(coalesce(p_holder_name, ''));
  v_nick        text := nullif(btrim(coalesce(p_nickname, '')), '');
  v_tok         jsonb;
  v_count       int;
  v_has_default boolean;
  v_default     boolean := false;
  v_card        linked_card;
begin
  if v_uid is null then
    raise exception 'Authentication is required' using errcode = '42501';
  end if;
  if length(v_holder) < 2 or length(v_holder) > 80 then
    raise exception 'invalid_holder_name' using errcode = '22023';
  end if;
  if v_nick is not null and length(v_nick) > 40 then
    raise exception 'invalid_nickname' using errcode = '22023';
  end if;

  -- Serialize per user so the 5-card limit and single default can't race.
  perform pg_advisory_xact_lock(hashtext('linked_card:' || v_uid::text));

  v_tok := mockgw_tokenize_card(p_number, p_exp_month, p_exp_year, p_cvc);

  if p_save then
    select count(*) into v_count
    from linked_card
    where profile_id = v_uid and is_saved and deleted_at is null;
    if v_count >= 5 then
      raise exception 'card_limit_reached' using errcode = 'P0001';
    end if;

    if exists (
      select 1 from linked_card
      where profile_id = v_uid and is_saved and deleted_at is null
        and brand = v_tok->>'brand' and last4 = v_tok->>'last4'
        and exp_month = p_exp_month and exp_year = p_exp_year
    ) then
      raise exception 'card_already_added' using errcode = 'P0001';
    end if;

    select exists (
      select 1 from linked_card
      where profile_id = v_uid and is_default and deleted_at is null
    ) into v_has_default;

    v_default := coalesce(p_make_default, false) or not v_has_default;
    if v_default then
      update linked_card set is_default = false
      where profile_id = v_uid and is_default;
    end if;
  end if;

  insert into linked_card (
    profile_id, gateway_token, brand, last4, exp_month, exp_year,
    holder_name, nickname, is_default, is_saved, test_scenario
  ) values (
    v_uid, v_tok->>'token', v_tok->>'brand', v_tok->>'last4',
    p_exp_month, p_exp_year, v_holder, v_nick,
    v_default, coalesce(p_save, true), v_tok->>'scenario'
  )
  returning * into v_card;

  return jsonb_build_object(
    'id',          v_card.id,
    'brand',       v_card.brand,
    'last4',       v_card.last4,
    'exp_month',   v_card.exp_month,
    'exp_year',    v_card.exp_year,
    'holder_name', v_card.holder_name,
    'nickname',    v_card.nickname,
    'is_default',  v_card.is_default,
    'is_saved',    v_card.is_saved,
    'created_at',  v_card.created_at
  );
end;
$$;

create or replace function list_linked_cards()
returns table (
  id          uuid,
  brand       text,
  last4       text,
  exp_month   smallint,
  exp_year    smallint,
  holder_name text,
  nickname    text,
  is_default  boolean,
  is_expired  boolean,
  created_at  timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select c.id, c.brand, c.last4, c.exp_month, c.exp_year, c.holder_name,
         c.nickname, c.is_default,
         mockgw_card_expired(c.exp_month, c.exp_year),
         c.created_at
  from linked_card c
  where c.profile_id = auth.uid() and c.is_saved and c.deleted_at is null
  order by c.is_default desc, c.created_at desc;
$$;

create or replace function remove_linked_card(p_card_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_card linked_card;
begin
  if v_uid is null then
    raise exception 'Authentication is required' using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(hashtext('linked_card:' || v_uid::text));

  select * into v_card
  from linked_card
  where id = p_card_id and profile_id = v_uid and deleted_at is null
  for update;
  if v_card.id is null then
    raise exception 'card_not_found' using errcode = 'P0002';
  end if;

  -- Soft delete: the token must survive so refunds to this card still work.
  update linked_card
  set deleted_at = now(), is_default = false
  where id = v_card.id;

  if v_card.is_default then
    update linked_card
    set is_default = true
    where id = (
      select id from linked_card
      where profile_id = v_uid and is_saved and deleted_at is null
      order by created_at desc
      limit 1
    );
  end if;
end;
$$;

create or replace function set_default_linked_card(p_card_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Authentication is required' using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(hashtext('linked_card:' || v_uid::text));

  if not exists (
    select 1 from linked_card
    where id = p_card_id and profile_id = v_uid and is_saved and deleted_at is null
  ) then
    raise exception 'card_not_found' using errcode = 'P0002';
  end if;

  update linked_card set is_default = false
  where profile_id = v_uid and is_default and id <> p_card_id;
  update linked_card set is_default = true
  where id = p_card_id;
end;
$$;

-- ------------------------------------------------------------
-- Grants
-- ------------------------------------------------------------
revoke all on function mockgw_luhn_valid(text) from public, anon, authenticated;
revoke all on function mockgw_card_brand(text) from public, anon, authenticated;
revoke all on function mockgw_card_expired(integer, integer) from public, anon, authenticated;
revoke all on function mockgw_tokenize_card(text, integer, integer, text) from public, anon, authenticated;
revoke all on function mockgw_replay(uuid, uuid) from public, anon, authenticated;
revoke all on function mockgw_record(uuid, uuid, text, numeric, text, text, text, text, uuid, uuid) from public, anon, authenticated;
revoke all on function mockgw_charge(uuid, uuid, numeric, text, uuid, uuid) from public, anon, authenticated;
revoke all on function mockgw_payout(uuid, uuid, numeric, text, uuid, uuid) from public, anon, authenticated;
revoke all on function mockgw_refund(uuid, uuid, numeric, text, uuid, uuid) from public, anon, authenticated;

grant execute on function mockgw_charge(uuid, uuid, numeric, text, uuid, uuid) to service_role;
grant execute on function mockgw_payout(uuid, uuid, numeric, text, uuid, uuid) to service_role;
grant execute on function mockgw_refund(uuid, uuid, numeric, text, uuid, uuid) to service_role;

revoke all on function add_linked_card(text, integer, integer, text, text, text, boolean, boolean) from public, anon;
revoke all on function list_linked_cards() from public, anon;
revoke all on function remove_linked_card(uuid) from public, anon;
revoke all on function set_default_linked_card(uuid) from public, anon;

grant execute on function add_linked_card(text, integer, integer, text, text, text, boolean, boolean) to authenticated;
grant execute on function list_linked_cards() to authenticated;
grant execute on function remove_linked_card(uuid) to authenticated;
grant execute on function set_default_linked_card(uuid) to authenticated;

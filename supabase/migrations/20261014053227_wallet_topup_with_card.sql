-- ============================================================
-- Task 2 (Part A): card-funded wallet top-up.
--   1. wallet_transaction gains description + metadata.
--   2. apply_wallet_transaction becomes ONE 7-arg function (old 5-arg dropped).
--   3. topup_wallet_with_card(card, amount, request_id) replaces the typed
--      top-up; the old topup_wallet(numeric) is no longer callable by clients.
-- ============================================================

alter table wallet_transaction
  add column if not exists description text,
  add column if not exists metadata jsonb not null default '{}'::jsonb;

-- Safety net against double-credit: one top-up credit per gateway charge,
-- even if two requests race past the application-level check.
create unique index if not exists uq_wallet_txn_topup_gateway
  on wallet_transaction ((metadata->>'gateway_transaction_id'))
  where type = 'topup' and metadata->>'gateway_transaction_id' is not null;

-- ------------------------------------------------------------
-- apply_wallet_transaction: same logic as 20260827094613, plus
-- description/metadata. Existing 5-arg callers keep working via defaults.
-- The wallet is now created with ON CONFLICT DO NOTHING before the row lock,
-- which removes the "two concurrent first transactions" race.
-- ------------------------------------------------------------
drop function if exists apply_wallet_transaction(uuid, wallet_txn_type, numeric, text, uuid);

create function apply_wallet_transaction(
  p_profile_id      uuid,
  p_type            wallet_txn_type,
  p_amount          numeric,            -- signed: positive credit, negative debit
  p_reference_table text  default null,
  p_reference_id    uuid  default null,
  p_description     text  default null,
  p_metadata        jsonb default '{}'::jsonb
)
returns wallet_transaction
language plpgsql
security definer
set search_path = public
as $$
declare
  v_wallet wallet;
  v_txn    wallet_transaction;
begin
  insert into wallet (profile_id) values (p_profile_id)
  on conflict (profile_id) do nothing;

  select * into v_wallet from wallet where profile_id = p_profile_id for update;

  if v_wallet.balance + p_amount < 0 then
    raise exception 'Insufficient wallet balance for profile %', p_profile_id
      using errcode = 'P0001';
  end if;

  update wallet set balance = balance + p_amount, updated_at = now()
  where id = v_wallet.id
  returning * into v_wallet;

  insert into wallet_transaction (
    wallet_id, type, amount, balance_after,
    reference_table, reference_id, description, metadata
  )
  values (
    v_wallet.id, p_type, p_amount, v_wallet.balance,
    p_reference_table, p_reference_id, p_description,
    coalesce(p_metadata, '{}'::jsonb)
  )
  returning * into v_txn;

  return v_txn;
end;
$$;

revoke all on function apply_wallet_transaction(uuid, wallet_txn_type, numeric, text, uuid, text, jsonb)
  from public, anon, authenticated;
grant execute on function apply_wallet_transaction(uuid, wallet_txn_type, numeric, text, uuid, text, jsonb)
  to service_role;

-- ------------------------------------------------------------
-- topup_wallet_with_card
-- Returns jsonb {status, wallet_transaction_id, gateway_reference,
--                new_balance, failure_code, failure_message}.
-- A gateway decline is RETURNED (status 'failed'), not raised, so the failed
-- gateway_transaction row is committed. Validation problems raise plain codes.
-- ------------------------------------------------------------
create function topup_wallet_with_card(
  p_linked_card_id uuid,
  p_amount         numeric,
  p_request_id     uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c_min constant numeric := 100;
  c_max constant numeric := 100000;
  v_uid     uuid := auth.uid();
  v_card    linked_card;
  v_gw      gateway_transaction;
  v_txn     wallet_transaction;
  v_balance numeric;
begin
  if v_uid is null then
    raise exception 'Authentication is required' using errcode = '42501';
  end if;
  if p_request_id is null then
    raise exception 'invalid_request';
  end if;
  if p_amount is null or p_amount <= 0 or p_amount <> round(p_amount, 2) then
    raise exception 'invalid_amount';
  end if;
  if p_amount < c_min then
    raise exception 'amount_too_low';
  end if;
  if p_amount > c_max then
    raise exception 'amount_too_high';
  end if;

  -- Card must belong to the caller and not be soft-deleted.
  select * into v_card
  from linked_card
  where id = p_linked_card_id and profile_id = v_uid and deleted_at is null;
  if v_card.id is null then
    raise exception 'card_not_found';
  end if;

  -- Serialise concurrent calls with the same (user, request id).
  perform pg_advisory_xact_lock(hashtextextended(v_uid::text || ':' || p_request_id::text, 0));

  -- A reused request id must describe the same operation.
  select * into v_gw
  from gateway_transaction
  where profile_id = v_uid and request_id = p_request_id;
  if v_gw.id is not null and (
       v_gw.kind <> 'charge'
    or v_gw.purpose is distinct from 'topup'
    or v_gw.amount <> p_amount
    or v_gw.linked_card_id is distinct from p_linked_card_id
  ) then
    raise exception 'request_id_conflict';
  end if;

  -- Idempotent per (profile, request_id): a repeat returns the stored row.
  v_gw := mockgw_charge(v_uid, p_linked_card_id, p_amount, 'topup', null, p_request_id);

  if v_gw.status <> 'succeeded' then
    select coalesce(balance, 0) into v_balance from wallet where profile_id = v_uid;
    return jsonb_build_object(
      'status', 'failed',
      'wallet_transaction_id', null,
      'gateway_reference', v_gw.gateway_reference,
      'new_balance', coalesce(v_balance, 0),
      'failure_code', v_gw.failure_code,
      'failure_message', v_gw.failure_message
    );
  end if;

  -- Already credited for this charge (retry)? Reuse that transaction.
  select wt.* into v_txn
  from wallet_transaction wt
  join wallet w on w.id = wt.wallet_id
  where w.profile_id = v_uid
    and wt.type = 'topup'
    and wt.metadata->>'gateway_transaction_id' = v_gw.id::text;

  if v_txn.id is null then
    v_txn := apply_wallet_transaction(
      v_uid, 'topup', p_amount, 'gateway_transaction', v_gw.id,
      'Card top-up',
      jsonb_build_object(
        'gateway_transaction_id', v_gw.id,
        'gateway_reference', v_gw.gateway_reference,
        'card_last4', v_card.last4,
        'card_brand', v_card.brand
      )
    );
  end if;

  select balance into v_balance from wallet where profile_id = v_uid;

  return jsonb_build_object(
    'status', 'succeeded',
    'wallet_transaction_id', v_txn.id,
    'gateway_reference', v_gw.gateway_reference,
    'new_balance', v_balance,
    'failure_code', null,
    'failure_message', null
  );
end;
$$;

revoke all on function topup_wallet_with_card(uuid, numeric, uuid) from public, anon, authenticated;
grant execute on function topup_wallet_with_card(uuid, numeric, uuid) to authenticated;

-- The old "mint money" RPC is closed to clients (kept for service_role/debug).
revoke all on function topup_wallet(numeric) from public, anon, authenticated;
grant execute on function topup_wallet(numeric) to service_role;

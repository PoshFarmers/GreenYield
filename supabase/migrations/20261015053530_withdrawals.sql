-- Task 6: withdraw wallet balance to a linked card (mock gateway payout).
do $$
begin
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname = 'public' and p.proname = 'apply_wallet_transaction' and p.pronargs = 7) then
    raise exception 'Task 2 migration missing: 7-arg apply_wallet_transaction';
  end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname = 'public' and p.proname = 'mockgw_payout') then
    raise exception 'Task 1 migration missing: mockgw_payout';
  end if;
end;
$$;

create table withdrawal (
  id                    uuid primary key default gen_random_uuid(),
  profile_id            uuid not null references profile(id) on delete cascade,
  linked_card_id        uuid references linked_card(id) on delete set null,
  amount                numeric not null check (amount > 0),
  fee                   numeric not null default 0 check (fee >= 0),
  net_amount            numeric not null check (net_amount > 0),
  status                text not null check (status in ('processing', 'completed', 'failed')),
  gateway_reference     text,
  failure_code          text,
  request_id            uuid,
  requested_at          timestamptz not null default now(),
  completed_at          timestamptz,
  wallet_transaction_id uuid references wallet_transaction(id) on delete set null
);

create unique index uq_withdrawal_request
  on withdrawal(profile_id, request_id) where request_id is not null;
create index idx_withdrawal_profile
  on withdrawal(profile_id, requested_at desc);

alter table withdrawal enable row level security;
create policy "withdrawal_select_own" on withdrawal
  for select using (auth.uid() = profile_id);
-- No write policies: only request_withdrawal() writes. Not synced to PowerSync.
revoke all on withdrawal from anon, authenticated;
grant select on withdrawal to authenticated;

-- Internal: result JSON shared by the fresh and replay paths.
create function withdrawal_json(p_w withdrawal, p_balance numeric)
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'status',            p_w.status,
    'withdrawal_id',     p_w.id,
    'amount',            p_w.amount,
    'fee',               p_w.fee,
    'net_amount',        p_w.net_amount,
    'gateway_reference', p_w.gateway_reference,
    'failure_code',      p_w.failure_code,
    'new_balance',       coalesce(p_balance, 0)
  );
$$;

revoke all on function withdrawal_json(withdrawal, numeric) from public, anon, authenticated;
grant execute on function withdrawal_json(withdrawal, numeric) to service_role;

-- Returns jsonb {status: completed|failed, withdrawal_id, amount, fee, net_amount,
-- gateway_reference, failure_code, new_balance}. A gateway failure is RETURNED
-- (money already reversed); validation problems raise plain codes.
create function request_withdrawal(
  p_card_id    uuid,
  p_amount     numeric,
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c_min   constant numeric := 500;
  c_daily constant numeric := 100000;
  c_fee   constant numeric := 0;
  v_uid     uuid := auth.uid();
  v_card    linked_card;
  v_w       withdrawal;
  v_gw      gateway_transaction;
  v_txn     wallet_transaction;
  v_used    numeric;
  v_balance numeric;
  v_net     numeric;
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
    raise exception 'withdrawal_amount_too_low';
  end if;
  if p_amount > c_daily then
    raise exception 'withdrawal_daily_limit_exceeded';
  end if;

  -- One withdrawal at a time per user: keeps the daily limit and balance checks race-free.
  perform pg_advisory_xact_lock(hashtextextended('withdrawal:' || v_uid::text, 0));

  -- Idempotent replay.
  select * into v_w from withdrawal where profile_id = v_uid and request_id = p_request_id;
  if v_w.id is not null then
    if v_w.amount <> p_amount or v_w.linked_card_id is distinct from p_card_id then
      raise exception 'request_id_conflict';
    end if;
    select balance into v_balance from wallet where profile_id = v_uid;
    return withdrawal_json(v_w, v_balance);
  end if;

  select * into v_card
  from linked_card
  where id = p_card_id and profile_id = v_uid and is_saved and deleted_at is null;
  if v_card.id is null then
    raise exception 'card_not_found';
  end if;

  -- Daily limit, day boundary in Colombo time. Reversed (failed) payouts don't count.
  select coalesce(sum(amount), 0) into v_used
  from withdrawal
  where profile_id = v_uid
    and status in ('processing', 'completed')
    and (requested_at at time zone 'Asia/Colombo')::date = (now() at time zone 'Asia/Colombo')::date;
  if v_used + p_amount > c_daily then
    raise exception 'withdrawal_daily_limit_exceeded';
  end if;

  insert into wallet (profile_id) values (v_uid) on conflict (profile_id) do nothing;
  select balance into v_balance from wallet where profile_id = v_uid for update;
  if v_balance < p_amount then
    raise exception 'withdrawal_insufficient_balance';
  end if;

  v_net := p_amount - c_fee;

  insert into withdrawal (profile_id, linked_card_id, amount, fee, net_amount, status, request_id)
  values (v_uid, v_card.id, p_amount, c_fee, v_net, 'processing', p_request_id)
  returning * into v_w;

  v_txn := apply_wallet_transaction(
    v_uid, 'withdrawal', -p_amount, 'withdrawal', v_w.id,
    'Withdrawal to card',
    jsonb_build_object(
      'withdrawal_id', v_w.id,
      'card_last4', v_card.last4,
      'card_brand', v_card.brand,
      'fee', c_fee,
      'net', v_net
    )
  );

  v_gw := mockgw_payout(v_uid, v_card.id, v_net, 'withdrawal', v_w.id, p_request_id);

  if v_gw.status = 'succeeded' then
    update withdrawal
    set status = 'completed', gateway_reference = v_gw.gateway_reference,
        completed_at = now(), wallet_transaction_id = v_txn.id
    where id = v_w.id
    returning * into v_w;

    update wallet_transaction
    set metadata = metadata || jsonb_build_object('gateway_reference', v_gw.gateway_reference)
    where id = v_txn.id;
  else
    -- Auto-reverse: the money goes straight back to the wallet.
    perform apply_wallet_transaction(
      v_uid, 'adjustment', p_amount, 'withdrawal', v_w.id,
      'Withdrawal reversed',
      jsonb_build_object(
        'reason', 'payout_failed',
        'withdrawal_id', v_w.id,
        'failure_code', coalesce(v_gw.failure_code, 'payout_failed'),
        'gateway_reference', v_gw.gateway_reference,
        'reverses_wallet_transaction_id', v_txn.id
      )
    );
    update withdrawal
    set status = 'failed',
        failure_code = coalesce(v_gw.failure_code, 'payout_failed'),
        gateway_reference = v_gw.gateway_reference,
        wallet_transaction_id = v_txn.id
    where id = v_w.id
    returning * into v_w;
  end if;

  select balance into v_balance from wallet where profile_id = v_uid;
  return withdrawal_json(v_w, v_balance);
end;
$$;

revoke all on function request_withdrawal(uuid, numeric, uuid) from public, anon, authenticated;
grant execute on function request_withdrawal(uuid, numeric, uuid) to authenticated;

create function list_withdrawals()
returns table (
  id                uuid,
  amount            numeric,
  fee               numeric,
  net_amount        numeric,
  status            text,
  failure_code      text,
  gateway_reference text,
  card_brand        text,
  card_last4        text,
  requested_at      timestamptz,
  completed_at      timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select w.id, w.amount, w.fee, w.net_amount, w.status, w.failure_code,
         w.gateway_reference, c.brand, c.last4, w.requested_at, w.completed_at
  from withdrawal w
  left join linked_card c on c.id = w.linked_card_id
  where w.profile_id = auth.uid()
  order by w.requested_at desc
  limit 100;
$$;

revoke all on function list_withdrawals() from public, anon, authenticated;
grant execute on function list_withdrawals() to authenticated;

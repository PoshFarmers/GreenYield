-- ============================================================
-- Wallet is the mandatory payout rail for farmers/drivers, and an optional
-- (incentivized) path for buyers.
-- ============================================================

create table wallet (
  id          uuid primary key default gen_random_uuid(),
  profile_id  uuid not null unique references profile(id) on delete cascade,
  balance     numeric not null default 0 check (balance >= 0),
  currency    text not null default 'LKR',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create trigger trg_wallet_updated_at before update on wallet for each row execute function set_updated_at();

create type wallet_txn_type as enum ('topup', 'payment', 'payout', 'refund', 'withdrawal', 'adjustment');

create table wallet_transaction (
  id               uuid primary key default gen_random_uuid(),
  wallet_id        uuid not null references wallet(id) on delete cascade,
  type             wallet_txn_type not null,
  amount           numeric not null check (amount <> 0), -- positive = credit, negative = debit
  balance_after    numeric not null,
  reference_table  text,  -- e.g. 'orders', 'refund', 'payment'
  reference_id     uuid,
  created_at       timestamptz not null default now()
);

create index idx_wallet_transaction_wallet on wallet_transaction(wallet_id, created_at);

alter table wallet enable row level security;
alter table wallet_transaction enable row level security;

create policy "wallet_select_own" on wallet for select using (auth.uid() = profile_id);
create policy "wallet_transaction_select_own" on wallet_transaction for select using (
  exists (select 1 from wallet w where w.id = wallet_transaction.wallet_id and w.profile_id = auth.uid())
);
-- balance/transaction writes are backend-only, done exclusively through the
-- atomic function below -- never accepted directly from client input.

-- The single place wallet.balance is ever mutated; prevents double-spend/race
-- conditions across concurrent operations.
create or replace function apply_wallet_transaction(
  p_profile_id      uuid,
  p_type            wallet_txn_type,
  p_amount          numeric, -- signed: positive credit, negative debit
  p_reference_table text default null,
  p_reference_id    uuid default null
)
returns wallet_transaction as $$
declare
  v_wallet  wallet;
  v_txn     wallet_transaction;
begin
  select * into v_wallet from wallet where profile_id = p_profile_id for update;
  if v_wallet.id is null then
    insert into wallet (profile_id) values (p_profile_id) returning * into v_wallet;
  end if;

  if v_wallet.balance + p_amount < 0 then
    raise exception 'Insufficient wallet balance for profile %', p_profile_id using errcode = 'P0001';
  end if;

  update wallet set balance = balance + p_amount, updated_at = now()
  where id = v_wallet.id
  returning * into v_wallet;

  insert into wallet_transaction (wallet_id, type, amount, balance_after, reference_table, reference_id)
  values (v_wallet.id, p_type, p_amount, v_wallet.balance, p_reference_table, p_reference_id)
  returning * into v_txn;

  return v_txn;
end;
$$ language plpgsql security definer;

-- Lock down: this is the only place balance is ever mutated. Must never be
-- callable directly by a client, or anyone could credit/debit any wallet.
revoke execute on function apply_wallet_transaction(uuid, wallet_txn_type, numeric, text, uuid) from public;
grant execute on function apply_wallet_transaction(uuid, wallet_txn_type, numeric, text, uuid) to service_role;

create type payment_method as enum ('card', 'wallet');
create type payment_status as enum ('pending', 'authorized', 'captured', 'failed', 'refunded');

create table payment (
  id                 uuid primary key default gen_random_uuid(),
  order_id           uuid not null unique references orders(id) on delete restrict,
  buyer_profile_id   uuid not null references buyer_profile(profile_id),
  method             payment_method not null,
  amount             numeric not null check (amount >= 0),
  status             payment_status not null default 'pending',
  gateway_reference  text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create index idx_payment_buyer on payment(buyer_profile_id);
create trigger trg_payment_updated_at before update on payment for each row execute function set_updated_at();

create table payment_transaction (
  id                uuid primary key default gen_random_uuid(),
  payment_id        uuid not null references payment(id) on delete cascade,
  attempt_no        int not null default 1,
  status            text not null,
  gateway_response  jsonb,
  created_at        timestamptz not null default now()
);

create index idx_payment_transaction_payment on payment_transaction(payment_id);

create type refund_request_status as enum ('pending', 'approved', 'rejected');

create table refund_request (
  id                 uuid primary key default gen_random_uuid(),
  order_id           uuid not null references orders(id),
  payment_id         uuid not null references payment(id),
  buyer_profile_id   uuid not null references buyer_profile(profile_id),
  reason             text,
  evidence_url       text,
  status             refund_request_status not null default 'pending',
  requested_at       timestamptz not null default now(),
  resolved_at        timestamptz,
  resolved_by        uuid references profile(id)
);

create index idx_refund_request_order on refund_request(order_id);

create type refund_type as enum ('automatic', 'manual');

create table refund (
  id                  uuid primary key default gen_random_uuid(),
  refund_request_id   uuid references refund_request(id),
  payment_id          uuid not null references payment(id),
  amount              numeric not null check (amount >= 0),
  refund_type         refund_type not null,
  processed_at        timestamptz not null default now(),
  created_at          timestamptz not null default now()
);

create index idx_refund_payment on refund(payment_id);

alter table payment enable row level security;
alter table payment_transaction enable row level security;
alter table refund_request enable row level security;
alter table refund enable row level security;

create policy "payment_select_buyer" on payment for select using (auth.uid() = buyer_profile_id);
create policy "payment_transaction_select_via_payment" on payment_transaction for select using (
  exists (select 1 from payment p where p.id = payment_transaction.payment_id and p.buyer_profile_id = auth.uid())
);

create policy "refund_request_select_own" on refund_request for select using (auth.uid() = buyer_profile_id);
create policy "refund_request_insert_own" on refund_request for insert with check (auth.uid() = buyer_profile_id);

create policy "refund_select_via_payment" on refund for select using (
  exists (select 1 from payment p where p.id = refund.payment_id and p.buyer_profile_id = auth.uid())
);

create or replace function evaluate_refund_eligibility(p_order_id uuid)
returns table (eligible boolean, reason text) as $$
declare
  v_order          orders;
  v_delivered_at   timestamptz;
  v_dispute_window interval := interval '48 hours';
begin
  select * into v_order from orders where id = p_order_id;

  if v_order.id is null then
    raise exception 'Order % not found', p_order_id;
  end if;

  if auth.uid() is distinct from v_order.buyer_profile_id
     and auth.uid() is distinct from v_order.farmer_profile_id then
    raise exception 'Not authorized to view refund eligibility for order %', p_order_id
      using errcode = '42501';
  end if;

  if v_order.status in ('placed', 'confirmed', 'assigned') then
    return query select true, 'automatic_full_refund_pre_pickup';
  elsif v_order.status in ('picked_up', 'in_transit') then
    return query select false, 'not_eligible_after_pickup';
  elsif v_order.status in ('delivered', 'completed') then
    select changed_at into v_delivered_at from order_status_history
    where order_id = p_order_id and status = 'delivered'
    order by changed_at desc limit 1;

    if v_delivered_at is not null and now() <= v_delivered_at + v_dispute_window then
      return query select true, 'within_dispute_window_manual_review';
    else
      return query select false, 'past_dispute_window';
    end if;
  else
    return query select false, 'not_eligible';
  end if;
end;
$$ language plpgsql stable security definer;

-- Processes an eligible refund: credits the buyer's wallet instantly (per 4.1,
-- wallet refunds are instant vs. bank/gateway timelines) and records the refund.
create or replace function process_refund(
  p_order_id           uuid,
  p_refund_request_id  uuid default null,
  p_amount             numeric default null
)
returns refund as $$
declare
  v_payment  payment;
  v_refund   refund;
  v_amount   numeric;
begin
  select * into v_payment from payment where order_id = p_order_id for update;

  if v_payment.id is null then
    raise exception 'No payment found for order %', p_order_id using errcode = 'P0001';
  end if;

  -- Idempotency guard: without this, calling process_refund twice for the
  -- same order double-credits the buyer's wallet.
  if v_payment.status = 'refunded' then
    raise exception 'Payment % has already been refunded', v_payment.id using errcode = 'P0001';
  end if;

  v_amount := coalesce(p_amount, v_payment.amount);

  insert into refund (refund_request_id, payment_id, amount, refund_type)
  values (p_refund_request_id, v_payment.id, v_amount,
          case when p_refund_request_id is null then 'automatic' else 'manual' end)
  returning * into v_refund;

  update payment set status = 'refunded', updated_at = now() where id = v_payment.id;

  -- Close out the originating request so it doesn't sit at 'pending' forever
  -- with no audit trail linking it to the refund that resolved it.
  if p_refund_request_id is not null then
    update refund_request
    set status = 'approved', resolved_at = now(), resolved_by = auth.uid()
    where id = p_refund_request_id;
  end if;

  perform apply_wallet_transaction(v_payment.buyer_profile_id, 'refund', v_amount, 'refund', v_refund.id);

  return v_refund;
end;
$$ language plpgsql security definer;

-- evaluate_refund_eligibility is read-only (no side effects) so it's safe
-- for any authenticated user to call directly, e.g. to show refund status
-- in the app before submitting a request.
revoke execute on function evaluate_refund_eligibility(uuid) from public;
grant execute on function evaluate_refund_eligibility(uuid) to authenticated;

-- process_refund moves real money -- must be backend-only.
revoke execute on function process_refund(uuid, uuid, numeric) from public;
grant execute on function process_refund(uuid, uuid, numeric) to service_role;

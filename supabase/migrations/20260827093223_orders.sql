-- ============================================================
-- Cart & Order Management
-- payment_id / delivery_id are added WITHOUT a FK here
-- ============================================================

create type order_status as enum (
  'placed', 'confirmed', 'assigned', 'picked_up', 'in_transit', 'delivered', 'completed', 'cancelled'
);

create table orders (
  id                   uuid primary key default gen_random_uuid(),
  checkout_group_id    uuid not null default gen_random_uuid(), -- ties sibling per-farmer orders from one checkout together
  buyer_profile_id     uuid not null references buyer_profile(profile_id),
  farmer_profile_id    uuid not null references farmer_profile(profile_id),
  status               order_status not null default 'placed',
  delivery_id          uuid, -- soft reference to delivery(id)  [Component 3]
  payment_id           uuid, -- soft reference to payment(id)   [Component 4]
  subtotal_amount      numeric not null check (subtotal_amount >= 0),
  delivery_fee_amount  numeric not null default 0 check (delivery_fee_amount >= 0),
  total_amount         numeric not null check (total_amount >= 0),
  delivery_address     jsonb,
  delivery_location    geography(Point, 4326),
  placed_at            timestamptz not null default now(),
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);

create index idx_orders_buyer          on orders(buyer_profile_id);
create index idx_orders_farmer         on orders(farmer_profile_id);
create index idx_orders_checkout_group on orders(checkout_group_id);
create index idx_orders_status         on orders(status);

create trigger trg_orders_updated_at before update on orders for each row execute function set_updated_at();

create table order_item (
  id                  uuid primary key default gen_random_uuid(),
  order_id            uuid not null references orders(id) on delete cascade,
  produce_listing_id  uuid not null references produce_listing(id),
  crop_id             uuid not null references crop(id), -- denormalized snapshot, survives listing edits
  quantity_kg         numeric not null check (quantity_kg > 0),
  price_per_kg        numeric not null check (price_per_kg >= 0), -- price snapshot at order time
  line_total          numeric generated always as (quantity_kg * price_per_kg) stored,
  created_at          timestamptz not null default now()
);

create index idx_order_item_order on order_item(order_id);

create table order_status_history (
  id          uuid primary key default gen_random_uuid(),
  order_id    uuid not null references orders(id) on delete cascade,
  status      order_status not null,
  changed_at  timestamptz not null default now(),
  changed_by  uuid references profile(id),
  note        text
);

create index idx_order_status_history_order on order_status_history(order_id, changed_at);

alter table orders enable row level security;
alter table order_item enable row level security;
alter table order_status_history enable row level security;

create policy "orders_select_buyer_or_farmer" on orders for select using (
  auth.uid() = buyer_profile_id or auth.uid() = farmer_profile_id
);
create policy "orders_insert_buyer" on orders for insert with check (auth.uid() = buyer_profile_id);
-- status/payment/delivery fields change only via the trusted functions below
-- (SECURITY DEFINER / service role) -- never via a direct client UPDATE.

create policy "order_item_select_via_order" on order_item for select using (
  exists (select 1 from orders o where o.id = order_item.order_id
          and (auth.uid() = o.buyer_profile_id or auth.uid() = o.farmer_profile_id))
);

create policy "order_status_history_select_via_order" on order_status_history for select using (
  exists (select 1 from orders o where o.id = order_status_history.order_id
          and (auth.uid() = o.buyer_profile_id or auth.uid() = o.farmer_profile_id))
);

-- Pure state-machine engine: enforces valid transitions only, no identity
-- check of its own. Reused internally by transition_delivery_status and any
-- future confirm/assign Edge Functions. Must stay service_role-only --
-- nothing here validates *who* is allowed to make the change, so it must
-- never be reachable directly by an authenticated client. (Nested calls from
-- other SECURITY DEFINER functions still work regardless of this grant,
-- since they execute as their own owner.)
create or replace function transition_order_status(
  p_order_id    uuid,
  p_new_status  order_status,
  p_changed_by  uuid default null,
  p_note        text default null
)
returns orders as $$
declare
  v_order   orders;
  v_allowed order_status[];
begin
  select * into v_order from orders where id = p_order_id for update;
  if v_order.id is null then
    raise exception 'Order % not found', p_order_id;
  end if;

  v_allowed := case v_order.status
    when 'placed'     then array['confirmed','cancelled']::order_status[]
    when 'confirmed'  then array['assigned','cancelled']::order_status[]
    when 'assigned'   then array['picked_up','cancelled']::order_status[]
    when 'picked_up'  then array['in_transit']::order_status[]
    when 'in_transit' then array['delivered']::order_status[]
    when 'delivered'  then array['completed']::order_status[]
    else array[]::order_status[]
  end;

  if not (p_new_status = any(v_allowed)) then
    raise exception 'Invalid transition from % to % for order %', v_order.status, p_new_status, p_order_id
      using errcode = 'P0001';
  end if;

  update orders set status = p_new_status, updated_at = now() where id = p_order_id
  returning * into v_order;

  insert into order_status_history (order_id, status, changed_by, note)
  values (p_order_id, p_new_status, p_changed_by, p_note);

  return v_order;
end;
$$ language plpgsql security definer;

-- Client-facing entry point: the ONLY order-status change a client may
-- trigger directly. Checks the caller is this order's buyer or farmer, then
-- delegates to the state machine above. Every other transition (confirm,
-- assign, picked_up, in_transit, delivered, completed) is driven by trusted
-- backend code and is not reachable by an authenticated client at all.
create or replace function cancel_order(
  p_order_id  uuid,
  p_note      text default null
)
returns orders as $$
declare
  v_order  orders;
begin
  select * into v_order from orders where id = p_order_id;
  if v_order.id is null then
    raise exception 'Order % not found', p_order_id;
  end if;

  if auth.uid() is distinct from v_order.buyer_profile_id
     and auth.uid() is distinct from v_order.farmer_profile_id then
    raise exception 'Not authorized to cancel order %', p_order_id
      using errcode = '42501';
  end if;

  return transition_order_status(p_order_id, 'cancelled', auth.uid(), p_note);
end;
$$ language plpgsql security definer;

revoke execute on function transition_order_status(uuid, order_status, uuid, text) from public;
grant execute on function transition_order_status(uuid, order_status, uuid, text) to service_role;

revoke execute on function cancel_order(uuid, text) from public;
grant execute on function cancel_order(uuid, text) to authenticated;

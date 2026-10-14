-- settlement at `delivered` for farmer AND driver.
-- Not in this migration (needs files not in the dump): notification restore in
-- transition_order_status, payout_received notifications, submit_farmer_review,
-- and scheduling complete_delivered_orders().

create table if not exists platform_config (
  key        text primary key,
  value      numeric not null,
  updated_at timestamptz not null default now()
);
insert into platform_config (key, value) values ('farmer_commission_rate', 0.03)
on conflict (key) do nothing;

create table if not exists platform_ledger (
  id         uuid primary key default gen_random_uuid(),
  order_id   uuid not null references orders(id) on delete restrict,
  kind       text not null check (kind in ('tax', 'commission')),
  amount     numeric not null check (amount >= 0),
  created_at timestamptz not null default now(),
  unique (order_id, kind)
);

alter table platform_config enable row level security;
alter table platform_ledger enable row level security;
revoke all on platform_config from anon, authenticated;
revoke all on platform_ledger from anon, authenticated;

-- One payout per wallet per reference (order for farmers, delivery for drivers).
create unique index if not exists uq_wallet_txn_payout_ref
  on wallet_transaction (wallet_id, reference_table, reference_id)
  where type = 'payout';

create or replace function settle_order(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order      orders;
  v_payment    payment;
  v_delivery   delivery;
  v_driver_id  uuid;
  v_rate       numeric;
  v_commission numeric;
  v_net        numeric;
  v_display    text;
  v_result     jsonb := jsonb_build_object('settled', true);
begin
  select * into v_order from orders where id = p_order_id for update;
  if v_order.id is null then
    raise exception 'Order % not found', p_order_id;
  end if;
  if v_order.status not in ('delivered', 'completed') then
    raise exception 'Order % is not delivered', p_order_id using errcode = 'P0001';
  end if;

  -- Never block a delivery: orders without a captured payment are simply not settled.
  select * into v_payment from payment where order_id = p_order_id;
  if v_payment.id is null or v_payment.status <> 'captured' then
    return jsonb_build_object('settled', false, 'reason', 'payment_not_captured');
  end if;

  v_display := 'GY-' || upper(substr(replace(p_order_id::text, '-', ''), 1, 6));
  v_rate := coalesce((select value from platform_config where key = 'farmer_commission_rate'), 0.03);
  v_commission := round(v_order.subtotal_amount * v_rate, 2);
  v_net := v_order.subtotal_amount - v_commission;

  -- Farmer: subtotal - commission.
  if v_net > 0 and not exists (
    select 1 from wallet_transaction wt join wallet w on w.id = wt.wallet_id
    where w.profile_id = v_order.farmer_profile_id and wt.type = 'payout'
      and wt.reference_table = 'orders' and wt.reference_id = p_order_id
  ) then
    perform apply_wallet_transaction(
      v_order.farmer_profile_id, 'payout', v_net, 'orders', p_order_id,
      'Order payout',
      jsonb_build_object(
        'order_id', p_order_id, 'order_display_id', v_display,
        'gross', v_order.subtotal_amount, 'commission', v_commission,
        'commission_rate', v_rate, 'net', v_net
      )
    );
    insert into platform_ledger (order_id, kind, amount) values (p_order_id, 'commission', v_commission)
    on conflict (order_id, kind) do nothing;
    if v_order.tax_amount > 0 then
      insert into platform_ledger (order_id, kind, amount) values (p_order_id, 'tax', v_order.tax_amount)
      on conflict (order_id, kind) do nothing;
    end if;
    v_result := v_result || jsonb_build_object('farmer_net', v_net, 'commission', v_commission);
  end if;

  -- Driver: the delivery fee (same reference as the legacy inline payout: 'delivery' + delivery id).
  select * into v_delivery from delivery where order_id = p_order_id;
  if v_delivery.id is not null and coalesce(v_order.delivery_fee_amount, 0) > 0 then
    select driver_profile_id into v_driver_id
    from delivery_assignment where delivery_id = v_delivery.id and is_current limit 1;

    if v_driver_id is not null and not exists (
      select 1 from wallet_transaction wt join wallet w on w.id = wt.wallet_id
      where w.profile_id = v_driver_id and wt.type = 'payout'
        and wt.reference_table = 'delivery' and wt.reference_id = v_delivery.id
    ) then
      perform apply_wallet_transaction(
        v_driver_id, 'payout', v_order.delivery_fee_amount, 'delivery', v_delivery.id,
        'Delivery payout',
        jsonb_build_object('order_id', p_order_id, 'order_display_id', v_display, 'delivery_id', v_delivery.id)
      );
      v_result := v_result || jsonb_build_object('driver_fee', v_order.delivery_fee_amount);
    end if;
  end if;

  return v_result;
end;
$$;

revoke all on function settle_order(uuid) from public, anon, authenticated;
grant execute on function settle_order(uuid) to service_role;

-- transition_delivery_status, copied from 20260916050308 (latest).
-- Only change: the inline driver payout is replaced by settle_order().
create or replace function transition_delivery_status(
  p_delivery_id  uuid,
  p_new_status   delivery_status
)
returns delivery as $$
declare
  v_delivery      delivery;
  v_order_status  order_status;
  v_caller        uuid := auth.uid();
begin
  if v_caller is not null and not exists (
    select 1 from delivery_assignment da
    where da.delivery_id = p_delivery_id
      and da.driver_profile_id = v_caller
      and da.is_current
  ) then
    raise exception 'Not authorized to change status of delivery %', p_delivery_id
      using errcode = '42501';
  end if;

  update delivery
  set status       = p_new_status,
      assigned_at  = case when p_new_status = 'assigned'  then now() else assigned_at  end,
      picked_up_at = case when p_new_status = 'picked_up' then now() else picked_up_at end,
      delivered_at = case when p_new_status = 'delivered' then now() else delivered_at end,
      updated_at   = now()
  where id = p_delivery_id
  returning * into v_delivery;

  if v_delivery.id is null then
    raise exception 'Delivery % not found', p_delivery_id;
  end if;

  v_order_status := case p_new_status
    when 'assigned'   then 'assigned'
    when 'picked_up'  then 'picked_up'
    when 'in_transit' then 'in_transit'
    when 'delivered'  then 'delivered'
    else null
  end;

  if v_order_status is not null then
    perform transition_order_status(v_delivery.order_id, v_order_status, null, 'auto: delivery status sync');
  end if;

  if p_new_status = 'delivered' then
    perform settle_order(v_delivery.order_id);
  end if;

  return v_delivery;
end;
$$ language plpgsql security definer;

-- anon must not be able to call this (a null auth.uid() skips the ownership check).
revoke all on function transition_delivery_status(uuid, delivery_status) from public, anon;
grant execute on function transition_delivery_status(uuid, delivery_status) to authenticated, service_role;

-- delivered -> completed after the 48h dispute window. NOT scheduled yet (see header).
create or replace function complete_delivered_orders()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_count integer := 0;
begin
  for r in
    select o.id
    from orders o
    where o.status = 'delivered'
      and coalesce(
            (select max(h.changed_at) from order_status_history h
             where h.order_id = o.id and h.status = 'delivered'),
            o.updated_at
          ) < now() - interval '48 hours'
  loop
    begin
      perform transition_order_status(r.id, 'completed', null, 'auto: dispute window elapsed');
      v_count := v_count + 1;
    exception when others then
      raise warning 'complete_delivered_orders: order % skipped: %', r.id, sqlerrm;
    end;
  end loop;
  return v_count;
end;
$$;

revoke all on function complete_delivered_orders() from public, anon, authenticated;
grant execute on function complete_delivered_orders() to service_role;

-- get_order_detail, copied from 20260915120000 (latest).
-- Added: tax_amount; payment info (buyer only); commission/net payout (farmer only);
-- delivery payout (driver only). Payout fields are null until the order is settled.
create or replace function get_order_detail(p_order_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid          uuid := auth.uid();
  v_order        orders;
  v_delivery     delivery;
  v_da           delivery_assignment;
  v_farmer       profile;
  v_buyer        profile;
  v_driver       profile;
  v_vehicle      vehicle;
  v_items        jsonb;
  v_payment      payment;
  v_card         linked_card;
  v_commission   numeric;
  v_is_buyer     boolean;
  v_is_farmer    boolean;
begin
  select * into v_order from orders where id = p_order_id;

  if v_order.id is null then
    raise exception 'Order not found' using errcode = 'P0002';
  end if;

  if v_order.buyer_profile_id <> v_uid
     and v_order.farmer_profile_id <> v_uid then
    if not exists (
      select 1
      from delivery d
      join delivery_assignment da on da.delivery_id = d.id and da.is_current
      where d.order_id = p_order_id and da.driver_profile_id = v_uid
    ) then
      raise exception 'Access denied' using errcode = '42501';
    end if;
  end if;

  v_is_buyer  := v_order.buyer_profile_id = v_uid;
  v_is_farmer := v_order.farmer_profile_id = v_uid;

  select * into v_delivery from delivery where order_id = p_order_id limit 1;

  if v_delivery.id is not null then
    select * into v_da
    from delivery_assignment
    where delivery_id = v_delivery.id and is_current = true
    limit 1;
  end if;

  select * into v_farmer from profile where id = v_order.farmer_profile_id;
  select * into v_buyer  from profile where id = v_order.buyer_profile_id;

  if v_da.driver_profile_id is not null then
    select * into v_driver  from profile where id = v_da.driver_profile_id;
    select * into v_vehicle from vehicle where driver_profile_id = v_da.driver_profile_id limit 1;
  end if;

  select * into v_payment from payment where order_id = p_order_id;
  if v_payment.linked_card_id is not null then
    select * into v_card from linked_card where id = v_payment.linked_card_id;
  end if;
  select amount into v_commission from platform_ledger
  where order_id = p_order_id and kind = 'commission';

  select jsonb_agg(
    jsonb_build_object(
      'id',            oi.id,
      'crop_id',       oi.crop_id,
      'crop_name',     c.name,
      'quantity_kg',   oi.quantity_kg,
      'price_per_kg',  oi.price_per_kg,
      'image_url',     coalesce(pl.image_url, fc.image_url, c.fallback_image_url)
    )
    order by oi.created_at
  )
  into v_items
  from order_item oi
  join crop c on c.id = oi.crop_id
  left join produce_listing pl on pl.id = oi.produce_listing_id
  left join farmer_crop fc
         on fc.farmer_profile_id = v_order.farmer_profile_id
        and fc.crop_id = oi.crop_id
  where oi.order_id = p_order_id;

  return jsonb_build_object(
    'id',                   v_order.id,
    'checkout_group_id',    v_order.checkout_group_id,
    'status',               v_order.status::text,
    'placed_at',            v_order.placed_at,
    'order_date',           v_order.order_date,
    'subtotal_amount',      v_order.subtotal_amount,
    'delivery_fee_amount',  v_order.delivery_fee_amount,
    'tax_amount',           v_order.tax_amount,
    'total_amount',         v_order.total_amount,
    'delivery_address',     v_order.delivery_address,
    'items',                coalesce(v_items, '[]'::jsonb),
    'farmer_profile_id',    v_order.farmer_profile_id,
    'farmer_name',          trim(coalesce(v_farmer.first_name, '') || ' ' || coalesce(v_farmer.last_name, '')),
    'farmer_phone',         v_farmer.phone,
    'buyer_profile_id',     v_order.buyer_profile_id,
    'buyer_name',           trim(coalesce(v_buyer.first_name, '') || ' ' || coalesce(v_buyer.last_name, '')),
    'buyer_phone',          v_buyer.phone,
    'delivery_id',          v_delivery.id,
    'delivery_status',      v_delivery.status::text,
    'driver_profile_id',    v_da.driver_profile_id,
    'driver_name',          case when v_driver.id is not null
                              then trim(coalesce(v_driver.first_name, '') || ' ' || coalesce(v_driver.last_name, ''))
                              else null end,
    'driver_phone',         v_driver.phone,
    'vehicle_type',         v_vehicle.vehicle_type::text,
    'vehicle_plate',        v_vehicle.plate_number,
    -- Task 3: payment info, buyer only
    'payment_method',       case when v_is_buyer then v_payment.method::text end,
    'payment_status',       case when v_is_buyer then v_payment.status::text end,
    'payment_card_last4',   case when v_is_buyer then v_card.last4 end,
    'payment_card_brand',   case when v_is_buyer then v_card.brand::text end,
    -- Task 4: settlement, role-specific, null until settled
    'commission_amount',    case when v_is_farmer then v_commission end,
    'net_payout',           case when v_is_farmer and v_commission is not null
                              then v_order.subtotal_amount - v_commission end,
    'driver_payout',        case when v_commission is not null and not coalesce(v_is_buyer, false)
                                  and not coalesce(v_is_farmer, false)
                              then v_order.delivery_fee_amount end
  );
end;
$$;

revoke all on function get_order_detail(uuid) from public, anon;
grant execute on function get_order_detail(uuid) to authenticated;

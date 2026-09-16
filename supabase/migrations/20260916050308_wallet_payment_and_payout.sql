-- ============================================================
-- Sprint 3 — Task 15.3: Payment Completion
--
--   1. Wallet payments now actually debit the buyer's wallet inside
--      place_checkout (via apply_wallet_transaction, built Sprint 2
--      but never called until now) and mark the payment 'captured'
--      immediately, since a wallet debit is instant — no gateway.
--   2. simulate_card_payment_capture() is a demo stand-in for a real
--      payment gateway webhook, so the 'card' path can also be
--      demoed end-to-end without a live integration.
--   3. transition_delivery_status() now pays the driver (via the same
--      apply_wallet_transaction) the moment a delivery is marked
--      'delivered', equal to that order's delivery_fee_amount.
-- ============================================================

create or replace function place_checkout(
  p_request_id      uuid,
  p_cart_items      jsonb,
  p_payment_method  text,
  p_delivery_address jsonb default null,
  p_order_date      date default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_buyer_id  uuid := auth.uid();
  v_cart_id   uuid;
  v_existing  jsonb;
  v_group_id  uuid := gen_random_uuid();
  v_now       timestamptz := now();
  v_order_date date := coalesce(p_order_date, (now()::date + 1));
  v_item      jsonb;
  v_cart_item cart_item;
  v_listing   produce_listing;
  v_subtotal  numeric;
  v_tax       numeric;
  v_fee       numeric;
  v_total     numeric;
  v_order_id  uuid;
  v_payment_id uuid;
  v_farmer_id uuid;
  v_result    jsonb := '[]'::jsonb;
  v_order     jsonb;
  v_items     jsonb;
  v_item_ids  uuid[] := '{}'::uuid[];
  v_line      record;
  v_buyer_location  geography;
  v_farmer_location geography;
begin
  if v_buyer_id is null then
    raise exception 'Authentication is required' using errcode = '42501';
  end if;

  if p_request_id is null or p_cart_items is null
     or jsonb_typeof(p_cart_items) <> 'array' or jsonb_array_length(p_cart_items) = 0 then
    raise exception 'Checkout requires at least one cart item' using errcode = '22023';
  end if;

  if p_payment_method not in ('wallet', 'card') then
    raise exception 'Unsupported payment method' using errcode = '22023';
  end if;

  select result into v_existing
  from checkout_request
  where id = p_request_id and buyer_profile_id = v_buyer_id;
  if v_existing is not null then
    return v_existing;
  end if;

  select id into v_cart_id from cart where buyer_profile_id = v_buyer_id for update;
  if v_cart_id is null then
    raise exception 'Cart not found' using errcode = 'P0001';
  end if;

  select location_point into v_buyer_location from profile where id = v_buyer_id;

  for v_item in select value from jsonb_array_elements(p_cart_items)
  loop
    if (v_item->>'id') is null or (v_item->>'quantity_kg')::numeric <= 0 then
      raise exception 'Invalid cart item' using errcode = '22023';
    end if;

    select * into v_cart_item
    from cart_item
    where id = (v_item->>'id')::uuid and cart_id = v_cart_id
    for update;
    if v_cart_item.id is null then
      raise exception 'Cart item does not belong to buyer' using errcode = '42501';
    end if;
    if (v_item->>'quantity_kg')::numeric <> v_cart_item.quantity_kg then
      raise exception 'Cart item quantity changed' using errcode = 'P0001';
    end if;
    v_item_ids := array_append(v_item_ids, v_cart_item.id);
  end loop;

  for v_cart_item in
    select ci.* from cart_item ci where ci.id = any(v_item_ids) order by ci.id for update
  loop
    select * into v_listing from produce_listing where id = v_cart_item.produce_listing_id for update;
    if v_listing.id is null or v_listing.status <> 'active'
       or (v_listing.expires_at is not null and v_listing.expires_at < v_now)
       or v_listing.available_quantity_kg < v_cart_item.quantity_kg then
      raise exception 'Listing is unavailable or has insufficient stock' using errcode = 'P0001';
    end if;
  end loop;

  for v_farmer_id in
    select distinct pl.farmer_profile_id
    from cart_item ci join produce_listing pl on pl.id = ci.produce_listing_id
    where ci.id = any(v_item_ids) order by pl.farmer_profile_id
  loop
    v_subtotal := 0;
    v_items := '[]'::jsonb;

    for v_line in
      select ci.id as cart_item_id,
             ci.quantity_kg,
             pl.id as listing_id,
             pl.crop_id,
             pl.price_per_kg,
             coalesce(pl.image_url, fc.image_url, c.fallback_image_url) as image_url,
             c.name as crop_name
      from cart_item ci
      join produce_listing pl on pl.id = ci.produce_listing_id
      join crop c on c.id = pl.crop_id
      left join farmer_crop fc on fc.farmer_profile_id = pl.farmer_profile_id and fc.crop_id = pl.crop_id
      where ci.id = any(v_item_ids) and pl.farmer_profile_id = v_farmer_id
      order by ci.id
    loop
      v_subtotal := v_subtotal + (v_line.quantity_kg * v_line.price_per_kg);
      v_items := v_items || jsonb_build_array(jsonb_build_object(
        'cart_item_id', v_line.cart_item_id,
        'produce_listing_id', v_line.listing_id,
        'crop_id', v_line.crop_id,
        'crop_name', v_line.crop_name,
        'quantity_kg', v_line.quantity_kg,
        'price_per_kg', v_line.price_per_kg,
        'line_total', v_line.quantity_kg * v_line.price_per_kg,
        'image_url', v_line.image_url
      ));
    end loop;

    select location_point into v_farmer_location from profile where id = v_farmer_id;
    if v_farmer_location is null or v_buyer_location is null then
      v_fee := 0;
    else
      v_fee := coalesce(calculate_delivery_fee(v_farmer_location, v_buyer_location), 0);
    end if;

    v_tax := round(v_subtotal * 0.02, 2);
    v_total := v_subtotal + v_fee + v_tax;
    v_order_id := gen_random_uuid();
    v_payment_id := gen_random_uuid();

    insert into orders (
      id, checkout_group_id, buyer_profile_id, farmer_profile_id, status,
      subtotal_amount, delivery_fee_amount, total_amount,
      delivery_address, order_date, placed_at, created_at, updated_at
    ) values (
      v_order_id, v_group_id, v_buyer_id, v_farmer_id, 'placed',
      v_subtotal, v_fee, v_total,
      p_delivery_address, v_order_date, v_now, v_now, v_now
    );

    insert into payment (id, order_id, buyer_profile_id, method, amount, status)
    values (v_payment_id, v_order_id, v_buyer_id, p_payment_method::payment_method, v_total, 'pending');

    update orders set payment_id = v_payment_id where id = v_order_id;

    -- Wallet payments are instant — no gateway round trip — so debit
    -- and capture happen right here. apply_wallet_transaction raises
    -- on insufficient balance, which rolls back the whole checkout
    -- (including any already-decremented listing stock), so a buyer
    -- can never be charged for less than the full checkout.
    if p_payment_method = 'wallet' then
      perform apply_wallet_transaction(
        v_buyer_id, 'payment', -v_total, 'orders', v_order_id
      );
      update payment set status = 'captured', updated_at = v_now where id = v_payment_id;
    end if;

    insert into order_item (order_id, produce_listing_id, crop_id, quantity_kg, price_per_kg)
    select v_order_id, (item->>'produce_listing_id')::uuid,
      (item->>'crop_id')::uuid, (item->>'quantity_kg')::numeric,
      (item->>'price_per_kg')::numeric
    from jsonb_array_elements(v_items) item;

    update produce_listing pl
    set available_quantity_kg = pl.available_quantity_kg - item.quantity_kg,
        status = case when pl.available_quantity_kg - item.quantity_kg <= 0 then 'sold_out' else pl.status end,
        updated_at = v_now
    from (
      select (item->>'produce_listing_id')::uuid as listing_id,
             (item->>'quantity_kg')::numeric as quantity_kg
      from jsonb_array_elements(v_items) item
    ) item
    where pl.id = item.listing_id;

    perform assign_nearest_driver(v_order_id);

    v_order := jsonb_build_object(
      'order_id', v_order_id,
      'farmer_profile_id', v_farmer_id,
      'items', v_items,
      'subtotal', v_subtotal,
      'delivery_fee', v_fee,
      'tax', v_tax,
      'total', v_total
    );
    v_result := v_result || jsonb_build_array(v_order);
  end loop;

  v_result := jsonb_build_object(
    'checkout_group_id', v_group_id,
    'order_ids', (select jsonb_agg(order_data->'order_id') from jsonb_array_elements(v_result) order_data),
    'orders', v_result,
    'placed_at', v_now,
    'order_date', v_order_date,
    'delivery_address', p_delivery_address
  );

  insert into checkout_request (id, buyer_profile_id, checkout_group_id, result)
  values (p_request_id, v_buyer_id, v_group_id, v_result);

  delete from cart_item where id = any(v_item_ids);
  return v_result;
end;
$$;

revoke all on function place_checkout(uuid, jsonb, text, jsonb, date) from public, anon;
grant execute on function place_checkout(uuid, jsonb, text, jsonb, date) to authenticated;

-- ------------------------------------------------------------
-- Demo stand-in for a real payment gateway webhook. Lets the app
-- demo the full 'card' payment lifecycle without a live gateway
-- integration — replace with a real webhook-driven capture before
-- production. Only the order's own buyer may call it.
-- ------------------------------------------------------------
create or replace function simulate_card_payment_capture(
  p_order_id uuid
)
returns payment
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment payment;
  v_order   orders;
begin
  select * into v_order from orders where id = p_order_id;
  if v_order.id is null then
    raise exception 'Order % not found', p_order_id;
  end if;
  if auth.uid() is distinct from v_order.buyer_profile_id then
    raise exception 'Not authorized' using errcode = '42501';
  end if;

  select * into v_payment from payment where order_id = p_order_id for update;
  if v_payment.id is null then
    raise exception 'No payment found for order %', p_order_id;
  end if;
  if v_payment.method <> 'card' then
    raise exception 'Payment for order % is not a card payment', p_order_id;
  end if;
  if v_payment.status = 'captured' then
    return v_payment;
  end if;

  update payment
  set status = 'captured',
      gateway_reference = 'DEMO-' || substr(v_payment.id::text, 1, 8),
      updated_at = now()
  where id = v_payment.id
  returning * into v_payment;

  return v_payment;
end;
$$;

revoke all on function simulate_card_payment_capture(uuid) from public, anon;
grant execute on function simulate_card_payment_capture(uuid) to authenticated;

-- ------------------------------------------------------------
-- Driver payout on delivery completion, equal to the delivery fee
-- collected for that order (delivery_fee_amount is now real, see
-- 20260915020000_dynamic_delivery_fee_checkout.sql).
-- ------------------------------------------------------------
create or replace function transition_delivery_status(
  p_delivery_id  uuid,
  p_new_status   delivery_status
)
returns delivery as $$
declare
  v_delivery      delivery;
  v_order         orders;
  v_order_status  order_status;
  v_caller        uuid := auth.uid();
  v_driver_id     uuid;
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

  select * into v_order from orders where id = v_delivery.order_id;

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

  if p_new_status = 'delivered' and v_order.id is not null then
    select driver_profile_id into v_driver_id
    from delivery_assignment
    where delivery_id = p_delivery_id and is_current
    limit 1;

    if v_driver_id is not null and coalesce(v_order.delivery_fee_amount, 0) > 0 then
      perform apply_wallet_transaction(
        v_driver_id, 'payout', v_order.delivery_fee_amount, 'delivery', p_delivery_id
      );
    end if;
  end if;

  return v_delivery;
end;
$$ language plpgsql security definer;

revoke execute on function transition_delivery_status(uuid, delivery_status) from public;
grant execute on function transition_delivery_status(uuid, delivery_status) to authenticated, service_role;
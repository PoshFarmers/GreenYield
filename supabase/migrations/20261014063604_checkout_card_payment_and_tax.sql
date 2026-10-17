-- card payment at checkout + orders.tax_amount.
do $$
begin
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname = 'public' and p.proname = 'apply_wallet_transaction' and p.pronargs = 7) then
    raise exception 'Task 2 migration missing: 7-arg apply_wallet_transaction not found';
  end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname = 'public' and p.proname = 'mockgw_charge') then
    raise exception 'Task 1 migration missing: mockgw_charge not found';
  end if;
end;
$$;

-- tax_amount: backfill = total - subtotal - delivery fee. Skip the updated_at bump.
alter table orders add column if not exists tax_amount numeric not null default 0 check (tax_amount >= 0);
alter table orders disable trigger trg_orders_updated_at;
update orders
set tax_amount = greatest(total_amount - subtotal_amount - delivery_fee_amount, 0)
where tax_amount = 0;
alter table orders enable trigger trg_orders_updated_at;

-- Which card paid (for Task 5 refunds). Not selected by any sync stream, so not synced.
alter table payment
  add column if not exists linked_card_id uuid references linked_card(id) on delete set null,
  add column if not exists gateway_transaction_id uuid references gateway_transaction(id) on delete set null;

-- Demo capture is no longer needed: card payments are captured inside place_checkout.
revoke all on function simulate_card_payment_capture(uuid) from public, anon, authenticated;
grant execute on function simulate_card_payment_capture(uuid) to service_role;

-- Never leave overloads. The 4-arg version (20260904170222) is stale: no wallet debit,
-- no driver assignment, and it was still granted to authenticated.
drop function if exists place_checkout(uuid, jsonb, text, jsonb);
drop function if exists place_checkout(uuid, jsonb, text, jsonb, date);

-- Payment handling for one checkout (all farmer orders of a group).
-- wallet: one debit per order. card: ONE gateway charge for the grand total.
-- Any failure raises, rolling back the whole checkout (declined attempts are not persisted).
create or replace function settle_checkout_payments(
  p_buyer_id   uuid,
  p_group_id   uuid,
  p_request_id uuid,
  p_method     text,
  p_card_id    uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total   numeric;
  v_balance numeric;
  v_gw      gateway_transaction;
  v_card    linked_card;
  v_rec     record;
begin
  select coalesce(sum(p.amount), 0) into v_total
  from payment p join orders o on o.id = p.order_id
  where o.checkout_group_id = p_group_id and p.buyer_profile_id = p_buyer_id;

  if p_method = 'wallet' then
    select balance into v_balance from wallet where profile_id = p_buyer_id for update;
    if coalesce(v_balance, 0) < v_total then
      raise exception 'insufficient_wallet_balance' using errcode = 'P0001';
    end if;

    for v_rec in
      select p.id as payment_id, p.amount, o.id as order_id
      from payment p join orders o on o.id = p.order_id
      where o.checkout_group_id = p_group_id and p.buyer_profile_id = p_buyer_id
      order by o.created_at, o.id
    loop
      perform apply_wallet_transaction(
        p_buyer_id, 'payment', -v_rec.amount, 'orders', v_rec.order_id,
        'Order payment',
        jsonb_build_object(
          'order_id', v_rec.order_id,
          'order_display_id', 'GY-' || upper(substr(replace(v_rec.order_id::text, '-', ''), 1, 6)),
          'checkout_group_id', p_group_id
        )
      );
      update payment set status = 'captured', updated_at = now() where id = v_rec.payment_id;
    end loop;

    return jsonb_build_object('method', 'wallet');
  end if;

  if p_method = 'card' then
    select * into v_card from linked_card
    where id = p_card_id and profile_id = p_buyer_id and deleted_at is null;
    if v_card.id is null then
      raise exception 'card_not_found' using errcode = 'P0001';
    end if;

    -- Dynamic call on purpose: literals adapt to mockgw_charge's parameter types
    -- (request_id / purpose_ref uuid vs text), which this migration does not depend on.
    execute format('select * from mockgw_charge(%L, %L, %L, %L, %L, %L)',
                   p_buyer_id, p_card_id, v_total, 'checkout', p_group_id, p_request_id)
      into v_gw;

    if v_gw.status::text <> 'succeeded' then
      raise exception 'card_declined:%', coalesce(v_gw.failure_code, 'card_declined')
        using errcode = 'P0001';
    end if;

    for v_rec in
      select p.id as payment_id, p.amount
      from payment p join orders o on o.id = p.order_id
      where o.checkout_group_id = p_group_id and p.buyer_profile_id = p_buyer_id
    loop
      update payment
      set status = 'captured',
          gateway_reference = v_gw.gateway_reference,
          linked_card_id = p_card_id,
          gateway_transaction_id = v_gw.id,
          updated_at = now()
      where id = v_rec.payment_id;

      insert into payment_transaction (payment_id, attempt_no, status, gateway_response)
      values (v_rec.payment_id, 1, 'succeeded', jsonb_build_object(
        'gateway_transaction_id', v_gw.id,
        'gateway_reference', v_gw.gateway_reference,
        'charged_total', v_total,
        'order_amount', v_rec.amount,
        'card_last4', v_card.last4,
        'card_brand', v_card.brand::text
      ));
    end loop;

    return jsonb_build_object(
      'method', 'card',
      'card_last4', v_card.last4,
      'card_brand', v_card.brand::text,
      'gateway_reference', v_gw.gateway_reference
    );
  end if;

  raise exception 'Unsupported payment method' using errcode = '22023';
end;
$$;

revoke all on function settle_checkout_payments(uuid, uuid, uuid, text, uuid) from public, anon, authenticated;
grant execute on function settle_checkout_payments(uuid, uuid, uuid, text, uuid) to service_role;

-- place_checkout, copied from 20260916050308 (latest). Changes vs that version:
--   + p_linked_card_id, early card validation, tax_amount stored on orders,
--   + wallet branch moved into settle_checkout_payments (called once after the loop),
--   + 'payment' object in the result.
-- Kept: order_date, dynamic delivery fee, assign_nearest_driver, checkout_request idempotency.
create or replace function place_checkout(
  p_request_id       uuid,
  p_cart_items       jsonb,
  p_payment_method   text,
  p_delivery_address jsonb default null,
  p_order_date       date default null,
  p_linked_card_id   uuid default null
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
  v_payment_info    jsonb;
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

  if p_payment_method = 'card' then
    if p_linked_card_id is null then
      raise exception 'card_required' using errcode = '22023';
    end if;
    perform 1 from linked_card
    where id = p_linked_card_id and profile_id = v_buyer_id and deleted_at is null;
    if not found then
      raise exception 'card_not_found' using errcode = 'P0001';
    end if;
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
      subtotal_amount, delivery_fee_amount, tax_amount, total_amount,
      delivery_address, order_date, placed_at, created_at, updated_at
    ) values (
      v_order_id, v_group_id, v_buyer_id, v_farmer_id, 'placed',
      v_subtotal, v_fee, v_tax, v_total,
      p_delivery_address, v_order_date, v_now, v_now, v_now
    );

    insert into payment (id, order_id, buyer_profile_id, method, amount, status)
    values (v_payment_id, v_order_id, v_buyer_id, p_payment_method::payment_method, v_total, 'pending');

    update orders set payment_id = v_payment_id where id = v_order_id;

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

  -- Wallet: debit per order. Card: one charge for the grand total. Raises on any failure.
  v_payment_info := settle_checkout_payments(
    v_buyer_id, v_group_id, p_request_id, p_payment_method, p_linked_card_id
  );

  v_result := jsonb_build_object(
    'checkout_group_id', v_group_id,
    'order_ids', (select jsonb_agg(order_data->'order_id') from jsonb_array_elements(v_result) order_data),
    'orders', v_result,
    'placed_at', v_now,
    'order_date', v_order_date,
    'delivery_address', p_delivery_address,
    'payment', v_payment_info
  );

  insert into checkout_request (id, buyer_profile_id, checkout_group_id, result)
  values (p_request_id, v_buyer_id, v_group_id, v_result);

  delete from cart_item where id = any(v_item_ids);
  return v_result;
end;
$$;

revoke all on function place_checkout(uuid, jsonb, text, jsonb, date, uuid) from public, anon, authenticated;
grant execute on function place_checkout(uuid, jsonb, text, jsonb, date, uuid) to authenticated;

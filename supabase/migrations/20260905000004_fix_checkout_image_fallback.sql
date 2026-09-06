-- Fix: ensure place_checkout returns the correct image fallback
-- so that the confirmation screen displays the correct image.
-- Falls back from produce_listing.image_url to farmer_crop.image_url
-- to crop.fallback_image_url.

create or replace function place_checkout(
  p_request_id uuid,
  p_cart_items jsonb,
  p_payment_method text,
  p_delivery_address jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_buyer_id uuid := auth.uid();
  v_cart_id uuid;
  v_existing jsonb;
  v_group_id uuid := gen_random_uuid();
  v_now timestamptz := now();
  v_item jsonb;
  v_cart_item cart_item;
  v_listing produce_listing;
  v_subtotal numeric;
  v_tax numeric;
  v_total numeric;
  v_order_id uuid;
  v_payment_id uuid;
  v_farmer_id uuid;
  v_result jsonb := '[]'::jsonb;
  v_order jsonb;
  v_items jsonb;
  v_item_ids uuid[] := '{}'::uuid[];
  v_line record;
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

    v_tax := round(v_subtotal * 0.02, 2);
    v_total := v_subtotal + v_tax;
    v_order_id := gen_random_uuid();
    v_payment_id := gen_random_uuid();

    insert into orders (
      id, checkout_group_id, buyer_profile_id, farmer_profile_id, status,
      payment_id, subtotal_amount, delivery_fee_amount, total_amount,
      delivery_address, placed_at, created_at, updated_at
    ) values (
      v_order_id, v_group_id, v_buyer_id, v_farmer_id, 'placed', null,
      v_subtotal, 0, v_total, p_delivery_address, v_now, v_now, v_now
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

    v_order := jsonb_build_object(
      'order_id', v_order_id,
      'farmer_profile_id', v_farmer_id,
      'items', v_items,
      'subtotal', v_subtotal,
      'delivery_fee', 0,
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
    'delivery_address', p_delivery_address
  );

  insert into checkout_request (id, buyer_profile_id, checkout_group_id, result)
  values (p_request_id, v_buyer_id, v_group_id, v_result);

  delete from cart_item where id = any(v_item_ids);
  return v_result;
end;
$$;

revoke all on function place_checkout(uuid, jsonb, text, jsonb) from public, anon;
grant execute on function place_checkout(uuid, jsonb, text, jsonb) to authenticated;

-- ============================================================
-- Provides a secure, cross-user read of the full order detail.
-- Because profile RLS only allows own-row reads, we use
-- SECURITY DEFINER so the function runs as the migration owner
-- (postgres/service_role) and can JOIN across profile rows.
-- 
-- Callers are verified: the calling user must be the buyer,
-- farmer, or assigned driver of the requested order.
-- ============================================================

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
begin
  -- Load the order first.
  select * into v_order from orders where id = p_order_id;

  if v_order.id is null then
    raise exception 'Order not found' using errcode = 'P0002';
  end if;

  -- Enforce access: only buyer, farmer, or assigned driver may call this.
  if v_order.buyer_profile_id <> v_uid
     and v_order.farmer_profile_id <> v_uid then
    -- Check if caller is the assigned driver.
    if not exists (
      select 1
      from delivery d
      join delivery_assignment da on da.delivery_id = d.id and da.is_current
      where d.order_id = p_order_id and da.driver_profile_id = v_uid
    ) then
      raise exception 'Access denied' using errcode = '42501';
    end if;
  end if;

  -- Delivery row (may be null if not yet assigned).
  select * into v_delivery from delivery where order_id = p_order_id limit 1;

  -- Current delivery assignment (may be null).
  if v_delivery.id is not null then
    select * into v_da
    from delivery_assignment
    where delivery_id = v_delivery.id and is_current = true
    limit 1;
  end if;

  -- Profiles (full rows — this function runs as superuser).
  select * into v_farmer from profile where id = v_order.farmer_profile_id;
  select * into v_buyer  from profile where id = v_order.buyer_profile_id;

  if v_da.driver_profile_id is not null then
    select * into v_driver  from profile where id = v_da.driver_profile_id;
    select * into v_vehicle from vehicle where driver_profile_id = v_da.driver_profile_id limit 1;
  end if;

  -- Order items with image_url from produce_listing (coalesce to crop fallback).
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
    -- Order core
    'id',                   v_order.id,
    'checkout_group_id',    v_order.checkout_group_id,
    'status',               v_order.status::text,
    'placed_at',            v_order.placed_at,
    'order_date',           v_order.order_date,
    'subtotal_amount',      v_order.subtotal_amount,
    'delivery_fee_amount',  v_order.delivery_fee_amount,
    'total_amount',         v_order.total_amount,
    'delivery_address',     v_order.delivery_address,
    -- Items
    'items',                coalesce(v_items, '[]'::jsonb),
    -- Farmer
    'farmer_profile_id',    v_order.farmer_profile_id,
    'farmer_name',          trim(coalesce(v_farmer.first_name, '') || ' ' || coalesce(v_farmer.last_name, '')),
    'farmer_phone',         v_farmer.phone,
    -- Buyer
    'buyer_profile_id',     v_order.buyer_profile_id,
    'buyer_name',           trim(coalesce(v_buyer.first_name, '') || ' ' || coalesce(v_buyer.last_name, '')),
    'buyer_phone',          v_buyer.phone,
    -- Delivery
    'delivery_id',          v_delivery.id,
    'delivery_status',      v_delivery.status::text,
    -- Driver
    'driver_profile_id',    v_da.driver_profile_id,
    'driver_name',          case when v_driver.id is not null
                              then trim(coalesce(v_driver.first_name, '') || ' ' || coalesce(v_driver.last_name, ''))
                              else null end,
    'driver_phone',         v_driver.phone,
    'vehicle_type',         v_vehicle.vehicle_type::text,
    'vehicle_plate',        v_vehicle.plate_number
  );
end;
$$;

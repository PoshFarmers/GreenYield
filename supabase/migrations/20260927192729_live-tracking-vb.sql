-- ============================================================
-- Support live tracking for Buyer and Farmer:
-- 1. `order_date` validation check / visibility helper logic:
--    Track order button is visible only when:
--    - Order status is active (assigned, packed, picked_up, in_transit)
--    - Today is the order's order_date (or order_date is null/placed_at is today)
--
-- 2. `get_live_order_tracking(p_order_id)` RPC:
--    Returns:
--    - `order_id`, `status`
--    - `is_picked_up` (boolean: true if status is picked_up, in_transit, delivered, completed)
--    - `order_date`
--    - `driver`: profile info + latest driver GPS ping (lat, lng, speed, heading, updated_at) from `delivery_tracking`
--    - `farmer` / `farmers`: profile location & info for farmer(s)
--    - `buyer`: profile location & info for buyer
-- ============================================================

create or replace function get_live_order_tracking(p_order_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid         uuid := auth.uid();
  v_order       orders;
  v_delivery    delivery;
  v_da          delivery_assignment;
  v_farmer      profile;
  v_buyer       profile;
  v_driver      profile;
  v_last_ping   delivery_tracking;
  v_is_picked   boolean;
begin
  select * into v_order from orders where id = p_order_id;
  if v_order.id is null then
    raise exception 'Order not found' using errcode = 'P0002';
  end if;

  -- Access control: caller must be buyer, farmer, or assigned driver.
  if v_order.buyer_profile_id <> v_uid and v_order.farmer_profile_id <> v_uid then
    if not exists (
      select 1
      from delivery d
      join delivery_assignment da on da.delivery_id = d.id and da.is_current
      where d.order_id = p_order_id and da.driver_profile_id = v_uid
    ) then
      raise exception 'Access denied' using errcode = '42501';
    end if;
  end if;

  select * into v_delivery from delivery where order_id = p_order_id limit 1;

  if v_delivery.id is not null then
    select * into v_da
    from delivery_assignment
    where delivery_id = v_delivery.id and is_current = true
    limit 1;

    select * into v_last_ping
    from delivery_tracking
    where delivery_id = v_delivery.id
    order by recorded_at desc
    limit 1;
  end if;

  select * into v_farmer from profile where id = v_order.farmer_profile_id;
  select * into v_buyer  from profile where id = v_order.buyer_profile_id;

  if v_da.driver_profile_id is not null then
    select * into v_driver from profile where id = v_da.driver_profile_id;
  end if;

  v_is_picked := (v_order.status in ('picked_up', 'in_transit', 'delivered', 'completed'));

  return jsonb_build_object(
    'order_id',          v_order.id,
    'status',            v_order.status::text,
    'order_date',        v_order.order_date,
    'placed_at',         v_order.placed_at,
    'is_picked_up',      v_is_picked,
    
    -- Driver payload
    'driver', case when v_driver.id is not null then jsonb_build_object(
      'id',              v_driver.id,
      'name',            trim(coalesce(v_driver.first_name, '') || ' ' || coalesce(v_driver.last_name, '')),
      'phone',           v_driver.phone,
      'latitude',        case when v_last_ping.id is not null then ST_Y(v_last_ping.location_point::geometry) else null end,
      'longitude',       case when v_last_ping.id is not null then ST_X(v_last_ping.location_point::geometry) else null end,
      'speed_kmh',       v_last_ping.speed_kmh,
      'heading',         v_last_ping.heading,
      'recorded_at',     v_last_ping.recorded_at
    ) else null end,

    -- Farmer payload
    'farmer', case when v_farmer.id is not null then jsonb_build_object(
      'id',              v_farmer.id,
      'name',            trim(coalesce(v_farmer.first_name, '') || ' ' || coalesce(v_farmer.last_name, '')),
      'phone',           v_farmer.phone,
      'address',         coalesce(v_farmer.location_text, v_farmer.address->>'line1'),
      'latitude',        case
                           when v_delivery.pickup_location_point is not null then ST_Y(v_delivery.pickup_location_point::geometry)
                           when v_farmer.location_point is not null then ST_Y(v_farmer.location_point::geometry)
                           else null
                         end,
      'longitude',       case
                           when v_delivery.pickup_location_point is not null then ST_X(v_delivery.pickup_location_point::geometry)
                           when v_farmer.location_point is not null then ST_X(v_farmer.location_point::geometry)
                           else null
                         end
    ) else null end,

    -- Buyer payload
    'buyer', case when v_buyer.id is not null then jsonb_build_object(
      'id',              v_buyer.id,
      'name',            trim(coalesce(v_buyer.first_name, '') || ' ' || coalesce(v_buyer.last_name, '')),
      'phone',           v_buyer.phone,
      'address',         coalesce(v_buyer.location_text, v_buyer.address->>'line1', v_order.delivery_address->>'line1'),
      'latitude',        case
                           when v_delivery.dropoff_location_point is not null then ST_Y(v_delivery.dropoff_location_point::geometry)
                           when v_buyer.location_point is not null then ST_Y(v_buyer.location_point::geometry)
                           else null
                         end,
      'longitude',       case
                           when v_delivery.dropoff_location_point is not null then ST_X(v_delivery.dropoff_location_point::geometry)
                           when v_buyer.location_point is not null then ST_X(v_buyer.location_point::geometry)
                           else null
                         end
    ) else null end
  );
end;
$$;

revoke all on function get_live_order_tracking(uuid) from public, anon;
grant execute on function get_live_order_tracking(uuid) to authenticated, service_role;

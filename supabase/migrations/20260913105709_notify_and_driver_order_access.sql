-- ============================================================
-- 1) Cache display names on `delivery` at assignment time so the
--    driver's calendar/app can show "Pickup at <farmer>" /
--    "Delivery to <buyer>" without widening `profile` RLS to
--    strangers — the driver only needs these two plain strings,
--    not full read access to the farmer/buyer profile rows.
-- ============================================================

alter table delivery
  add column farmer_display_name  text,
  add column buyer_display_name   text;

create or replace function assign_nearest_driver(
  p_order_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order            orders;
  v_farmer_location  geography;
  v_buyer_location   geography;
  v_farmer_name      text;
  v_buyer_name       text;
  v_driver_id        uuid;
  v_vehicle_id       uuid;
  v_delivery_id      uuid;
begin
  select * into v_order from orders where id = p_order_id;
  if v_order.id is null then
    raise exception 'Order % not found', p_order_id;
  end if;

  select location_point, trim(first_name || ' ' || last_name)
  into v_farmer_location, v_farmer_name
  from profile where id = v_order.farmer_profile_id;

  select location_point, trim(first_name || ' ' || last_name)
  into v_buyer_location, v_buyer_name
  from profile where id = v_order.buyer_profile_id;

  if v_farmer_location is null then
    -- Can't sort by distance without the farmer's location; leave
    -- the order unassigned for manual/dispatcher follow-up.
    return;
  end if;

  -- Nearest driver-with-a-vehicle to the farmer, sorted ascending
  -- by straight-line distance.
  select p.id, veh.id
  into v_driver_id, v_vehicle_id
  from profile p
  join driver_profile dp on dp.profile_id = p.id
  join vehicle veh on veh.driver_profile_id = dp.profile_id
  where p.location_point is not null
  order by ST_Distance(p.location_point, v_farmer_location) asc, veh.created_at asc
  limit 1;

  if v_driver_id is null then
    -- No driver with both a location and a vehicle exists yet.
    return;
  end if;

  insert into delivery (
    order_id, pickup_location_point, dropoff_location_point,
    farmer_display_name, buyer_display_name,
    status, assigned_at
  ) values (
    p_order_id, v_farmer_location, v_buyer_location,
    v_farmer_name, v_buyer_name,
    'assigned', now()
  )
  returning id into v_delivery_id;

  insert into delivery_assignment (delivery_id, driver_profile_id, vehicle_id)
  values (v_delivery_id, v_driver_id, v_vehicle_id);

  update orders set delivery_id = v_delivery_id where id = p_order_id;

  -- 'placed' can only move to 'assigned' via 'confirmed' (see the
  -- state machine in transition_order_status); auto-confirm is
  -- fine here since the assignment itself just proved the order is
  -- dispatchable.
  perform transition_order_status(p_order_id, 'confirmed', null, 'auto: nearest driver found');
  perform transition_order_status(p_order_id, 'assigned', null, 'auto: nearest driver assigned');
end;
$$;

-- ============================================================
-- 2) Let the assigned driver read the order/items/crop tied to
--    their current delivery — they're neither buyer nor farmer, so
--    the existing orders/order_item policies don't cover them.
-- ============================================================

create policy "orders_select_assigned_driver" on orders for select using (
  exists (
    select 1 from delivery d
    join delivery_assignment da on da.delivery_id = d.id
    where d.order_id = orders.id
      and da.driver_profile_id = auth.uid()
      and da.is_current
  )
);

create policy "order_item_select_assigned_driver" on order_item for select using (
  exists (
    select 1 from delivery d
    join delivery_assignment da on da.delivery_id = d.id
    where d.order_id = order_item.order_id
      and da.driver_profile_id = auth.uid()
      and da.is_current
  )
);

-- ============================================================
-- 3) Richer, two-sided assignment notifications: the driver hears
--    what/where the pickup is, and the buyer hears who's bringing
--    their order.
-- ============================================================

create or replace function notify_delivery_assignment() returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order  orders;
begin
  if new.is_current then
    select * into v_order from orders where id = (select order_id from delivery where id = new.delivery_id);

    perform send_notification(
      new.driver_profile_id,
      'delivery_assigned',
      'New pickup assigned',
      format(
        'Pickup from %s for order %s. Check the details before heading out.',
        coalesce((select farmer_display_name from delivery where id = new.delivery_id), 'a farmer'),
        v_order.id
      ),
      jsonb_build_object('delivery_id', new.delivery_id, 'order_id', v_order.id),
      'delivery',
      new.delivery_id
    );

    if v_order.id is not null then
      perform send_notification(
        v_order.buyer_profile_id,
        'order_driver_assigned',
        'Driver on the way',
        format(
          '%s has been assigned to deliver your order.',
          coalesce((select trim(first_name || ' ' || last_name) from profile where id = new.driver_profile_id), 'A driver')
        ),
        jsonb_build_object('order_id', v_order.id, 'delivery_id', new.delivery_id),
        'orders',
        v_order.id
      );
    end if;
  end if;
  return new;
end;
$$;

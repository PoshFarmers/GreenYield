-- ============================================================
-- Fix 3 issues after order placement:
--
--   1. Driver notification never fired: the replacement
--      notify_delivery_assignment() calls send_notification()
--      which is only granted to service_role, but the trigger
--      function owner may not have that privilege at runtime.
--      → Inline the INSERT directly into `notification` so there
--        is no cross-function grant dependency.
--
--   2. Buyer notification missing: same root cause as #1 — the
--      send_notification() call for the buyer was inside the same
--      security-definer trigger function and silently failed.
--
--   3. Driver calendar not updated: assign_nearest_driver()
--      creates delivery + delivery_assignment rows but never
--      touches driver_schedule, so the driver's calendar stays
--      blank.  → Upsert a driver_schedule row for the order date.
-- ============================================================

-- ============================================================
-- Fix 1 & 2 — two-sided assignment notifications (inlined INSERT)
-- ============================================================
create or replace function notify_delivery_assignment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order       orders;
  v_delivery    delivery;
  v_driver_name text;
begin
  if new.is_current then
    -- Resolve the delivery and its order.
    select * into v_delivery from delivery where id = new.delivery_id;
    select * into v_order    from orders    where id = v_delivery.order_id;

    -- Driver display name for the buyer-facing message.
    select trim(coalesce(first_name,'') || ' ' || coalesce(last_name,''))
    into v_driver_name
    from profile
    where id = new.driver_profile_id;

    -- ── Notify the DRIVER ──────────────────────────────────────
    insert into notification (
      profile_id, type, title, body, payload, source_table, source_id
    ) values (
      new.driver_profile_id,
      'delivery_assigned',
      'New pickup assigned',
      format(
        'Pickup from %s for order %s. Check the details before heading out.',
        coalesce(v_delivery.farmer_display_name, 'a farmer'),
        v_order.id
      ),
      jsonb_build_object(
        'delivery_id', new.delivery_id,
        'order_id',    v_order.id
      ),
      'delivery',
      new.delivery_id
    );

    -- ── Notify the BUYER ───────────────────────────────────────
    if v_order.buyer_profile_id is not null then
      insert into notification (
        profile_id, type, title, body, payload, source_table, source_id
      ) values (
        v_order.buyer_profile_id,
        'order_driver_assigned',
        'Driver on the way',
        format(
          '%s has been assigned to deliver your order.',
          coalesce(nullif(trim(v_driver_name), ''), 'A driver')
        ),
        jsonb_build_object(
          'order_id',    v_order.id,
          'delivery_id', new.delivery_id
        ),
        'orders',
        v_order.id
      );
    end if;
  end if;

  return new;
end;
$$;

-- Drop and re-create to guarantee the trigger points at the new body.
drop trigger if exists trg_notify_delivery_assignment on delivery_assignment;

create trigger trg_notify_delivery_assignment
  after insert on delivery_assignment
  for each row execute function notify_delivery_assignment();

-- ============================================================
-- Fix 3 — upsert a driver_schedule row when a driver is assigned
-- ============================================================
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
  v_delivery_date    date;
  v_max_capacity     numeric;
begin
  select * into v_order from orders where id = p_order_id;
  if v_order.id is null then
    raise exception 'Order % not found', p_order_id;
  end if;

  select location_point,
         trim(coalesce(first_name,'') || ' ' || coalesce(last_name,''))
  into v_farmer_location, v_farmer_name
  from profile where id = v_order.farmer_profile_id;

  select location_point,
         trim(coalesce(first_name,'') || ' ' || coalesce(last_name,''))
  into v_buyer_location, v_buyer_name
  from profile where id = v_order.buyer_profile_id;

  if v_farmer_location is null then
    -- Can't sort by distance without the farmer's location; leave
    -- the order unassigned for manual/dispatcher follow-up.
    return;
  end if;

  -- Nearest driver-with-a-vehicle to the farmer, ascending by distance.
  select p.id, veh.id, veh.max_load_kg
  into v_driver_id, v_vehicle_id, v_max_capacity
  from profile p
  join driver_profile dp  on dp.profile_id        = p.id
  join vehicle        veh on veh.driver_profile_id = dp.profile_id
  where p.location_point is not null
  order by ST_Distance(p.location_point, v_farmer_location) asc,
           veh.created_at asc
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

  -- ── Fix 3: keep the driver's calendar in sync ──────────────
  -- Use placed_at as the expected delivery date; fall back to today.
  v_delivery_date := coalesce(v_order.placed_at::date, current_date);

  insert into driver_schedule (
    driver_profile_id, schedule_date, is_available, max_capacity_kg
  ) values (
    v_driver_id,
    v_delivery_date,
    true,
    v_max_capacity
  )
  on conflict (driver_profile_id, schedule_date) do update set
    is_available    = true,
    max_capacity_kg = coalesce(driver_schedule.max_capacity_kg, excluded.max_capacity_kg),
    updated_at      = now();

  -- State-machine: placed → confirmed → assigned
  perform transition_order_status(p_order_id, 'confirmed', null, 'auto: nearest driver found');
  perform transition_order_status(p_order_id, 'assigned',  null, 'auto: nearest driver assigned');
end;
$$;

revoke all on function assign_nearest_driver(uuid) from public, anon, authenticated;
grant execute on function assign_nearest_driver(uuid) to service_role;

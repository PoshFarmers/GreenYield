-- ============================================================
-- Bug: assign_nearest_driver() upserts a driver_schedule row
-- using `placed_at::date` (i.e. today) as the delivery date
-- instead of `order_date` (the date the buyer actually selected).
--
-- Impact: any order whose `order_date` differs from `placed_at`
-- (e.g. an order placed on Sep 15 for Sep 17) will never appear
-- in the driver's Calendar or Deliveries screen — both of which
-- join delivery_assignment and filter by driver_schedule.schedule_date.
--
-- Fix:
--   1. Redefine assign_nearest_driver() to use
--      coalesce(v_order.order_date, v_order.placed_at::date, current_date)
--      for the driver_schedule upsert.
--   2. Backfill every driver_schedule row whose date doesn't
--      match the underlying order's order_date (covers the Sep 17
--      order and any others created since 20260913170000).
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
    return;
  end if;

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

  -- ── FIX: use order_date (buyer-selected delivery date), not placed_at ──
  -- Previously this was `v_order.placed_at::date`, which caused all orders
  -- whose delivery date differs from their placement date to be invisible
  -- in the driver Calendar and Deliveries screens.
  v_delivery_date := coalesce(v_order.order_date, v_order.placed_at::date, current_date);

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

  perform transition_order_status(p_order_id, 'confirmed', null, 'auto: nearest driver found');
  perform transition_order_status(p_order_id, 'assigned',  null, 'auto: nearest driver assigned');
end;
$$;

revoke all on function assign_nearest_driver(uuid) from public, anon, authenticated;
grant execute on function assign_nearest_driver(uuid) to service_role;

-- ============================================================
-- Backfill: fix existing driver_schedule rows whose date was
-- incorrectly set to placed_at::date instead of order_date.
-- For each affected delivery_assignment, delete the wrong-date
-- driver_schedule row and upsert the correct one.
-- ============================================================
do $$
declare
  r record;
begin
  for r in
    select
      da.driver_profile_id,
      o.id          as order_id,
      o.placed_at::date                                            as wrong_date,
      coalesce(o.order_date, o.placed_at::date, current_date)     as correct_date,
      v.max_load_kg
    from delivery_assignment da
    join delivery d  on d.id       = da.delivery_id
    join orders   o  on o.id       = d.order_id
    join vehicle  v  on v.id       = da.vehicle_id
    where da.is_current
      -- only rows where the dates actually differ
      and coalesce(o.order_date, o.placed_at::date) <> o.placed_at::date
  loop
    -- Remove the incorrectly-dated schedule row if it exists and
    -- is not shared by another delivery on that same day.
    -- (safe to delete: we'll re-create the correct one below)
    delete from driver_schedule
    where driver_profile_id = r.driver_profile_id
      and schedule_date     = r.wrong_date
      -- only delete if no OTHER order on that driver falls on wrong_date
      and not exists (
        select 1
        from delivery_assignment da2
        join delivery d2 on d2.id = da2.delivery_id
        join orders   o2 on o2.id = d2.order_id
        where da2.driver_profile_id = r.driver_profile_id
          and da2.is_current
          and da2.delivery_id <> (
            select id from delivery where order_id = r.order_id limit 1
          )
          and coalesce(o2.order_date, o2.placed_at::date, current_date) = r.wrong_date
      );

    -- Upsert with the correct order_date.
    insert into driver_schedule (
      driver_profile_id, schedule_date, is_available, max_capacity_kg
    ) values (
      r.driver_profile_id,
      r.correct_date,
      true,
      r.max_load_kg
    )
    on conflict (driver_profile_id, schedule_date) do update set
      is_available    = true,
      max_capacity_kg = coalesce(driver_schedule.max_capacity_kg, excluded.max_capacity_kg),
      updated_at      = now();

    raise notice 'Moved driver_schedule for driver % from % to % (order %)',
      r.driver_profile_id, r.wrong_date, r.correct_date, r.order_id;
  end loop;
end;
$$;

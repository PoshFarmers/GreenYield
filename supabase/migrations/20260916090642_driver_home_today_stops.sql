-- ============================================================
-- Driver Home Screen support:
--   1. get_driver_today_stops(p_driver_id) — every pickup/dropoff
--      stop for deliveries currently assigned to this driver whose
--      order is scheduled for today (order_date = current_date,
--      falling back to assigned_at's day for older rows without
--      order_date), with lat/lng pulled out of the geography
--      columns so the client can plot them on a map without doing
--      any PostGIS work itself.
--   2. start_driver_shift(p_order_ids) — called once when the
--      driver taps "Start Route"; notifies every buyer and farmer
--      on today's route that the driver is on the way. Reuses the
--      existing send_notification() helper from
--      20260829050340_notification_events.sql.
-- ============================================================

create or replace function get_driver_today_stops(p_driver_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_caller uuid := auth.uid();
  v_result jsonb;
begin
  -- A signed-in client may only ever ask for their own stops; a null
  -- caller (service_role) may ask for anyone's.
  if v_caller is not null and v_caller <> p_driver_id then
    raise exception 'Not authorized to read another driver''s stops'
      using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(stop order by stop_order), '[]'::jsonb)
  into v_result
  from (
    -- Pickup stop (at the farmer).
    select
      jsonb_build_object(
        'stop_type', 'pickup',
        'order_id', o.id,
        'delivery_id', d.id,
        'order_status', o.status::text,
        'delivery_status', d.status::text,
        'counterpart_name', coalesce(
          nullif(trim(coalesce(p_farmer.first_name, '') || ' ' || coalesce(p_farmer.last_name, '')), ''),
          d.farmer_display_name
        ),
        'counterpart_phone', p_farmer.phone,
        'address', coalesce(p_farmer.location_text, p_farmer.address->>'line1'),
        'latitude', ST_Y(d.pickup_location_point::geometry),
        'longitude', ST_X(d.pickup_location_point::geometry),
        'crop_names', (
          select string_agg(distinct c.name, ', ')
          from order_item oi join crop c on c.id = oi.crop_id
          where oi.order_id = o.id
        ),
        'total_amount', o.total_amount,
        'order_date', o.order_date,
        'assigned_at', d.assigned_at
      ) as stop,
      0 as stop_order,
      d.assigned_at as sort_time
    from delivery_assignment da
    join delivery d on d.id = da.delivery_id
    join orders   o on o.id = d.order_id
    left join profile p_farmer on p_farmer.id = o.farmer_profile_id
    where da.driver_profile_id = p_driver_id
      and da.is_current
      and o.status not in ('cancelled')
      and coalesce(o.order_date, (d.assigned_at at time zone 'utc')::date) = current_date
      and d.status in ('assigned')

    union all

    -- Dropoff stop (at the buyer) — shown once the order has been
    -- picked up (or later), so it doesn't jump ahead of the pickup
    -- stop while still `assigned`.
    select
      jsonb_build_object(
        'stop_type', 'dropoff',
        'order_id', o.id,
        'delivery_id', d.id,
        'order_status', o.status::text,
        'delivery_status', d.status::text,
        'counterpart_name', coalesce(
          nullif(trim(coalesce(p_buyer.first_name, '') || ' ' || coalesce(p_buyer.last_name, '')), ''),
          d.buyer_display_name
        ),
        'counterpart_phone', p_buyer.phone,
        'address', coalesce(p_buyer.location_text, p_buyer.address->>'line1', o.delivery_address->>'line1'),
        'latitude', ST_Y(d.dropoff_location_point::geometry),
        'longitude', ST_X(d.dropoff_location_point::geometry),
        'crop_names', (
          select string_agg(distinct c.name, ', ')
          from order_item oi join crop c on c.id = oi.crop_id
          where oi.order_id = o.id
        ),
        'total_amount', o.total_amount,
        'order_date', o.order_date,
        'assigned_at', d.assigned_at
      ) as stop,
      1 as stop_order,
      d.assigned_at as sort_time
    from delivery_assignment da
    join delivery d on d.id = da.delivery_id
    join orders   o on o.id = d.order_id
    left join profile p_buyer on p_buyer.id = o.buyer_profile_id
    where da.driver_profile_id = p_driver_id
      and da.is_current
      and o.status not in ('cancelled')
      and coalesce(o.order_date, (d.assigned_at at time zone 'utc')::date) = current_date
      and d.status in ('picked_up', 'in_transit', 'delivered')
  ) stops;

  return v_result;
end;
$$;

revoke all on function get_driver_today_stops(uuid) from public, anon;
grant execute on function get_driver_today_stops(uuid) to authenticated, service_role;

-- ------------------------------------------------------------
-- Driver taps "Start Route": notify every buyer/farmer on today's
-- assigned orders that the driver is starting their run. Ownership
-- is checked per order (caller must be the currently-assigned
-- driver), so one bad id in the array can't be used to spam an
-- unrelated pair of users.
-- ------------------------------------------------------------
create or replace function start_driver_shift(p_order_ids uuid[])
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller uuid := auth.uid();
  v_row record;
begin
  if v_caller is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  for v_row in
    select o.id as order_id, o.buyer_profile_id, o.farmer_profile_id
    from orders o
    join delivery d on d.order_id = o.id
    join delivery_assignment da on da.delivery_id = d.id and da.is_current
    where o.id = any(p_order_ids)
      and da.driver_profile_id = v_caller
  loop
    perform send_notification(
      v_row.buyer_profile_id,
      'driver_started_route',
      'Your driver is on the way',
      'Your driver has started today''s deliveries — you''re on the route.',
      jsonb_build_object('order_id', v_row.order_id),
      'orders',
      v_row.order_id
    );
    perform send_notification(
      v_row.farmer_profile_id,
      'driver_started_route',
      'Driver started their route',
      'The assigned driver has started today''s deliveries.',
      jsonb_build_object('order_id', v_row.order_id),
      'orders',
      v_row.order_id
    );
  end loop;
end;
$$;

revoke all on function start_driver_shift(uuid[]) from public, anon;
grant execute on function start_driver_shift(uuid[]) to authenticated;

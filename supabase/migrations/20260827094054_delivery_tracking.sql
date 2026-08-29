-- ============================================================
-- MAIN COMPONENT 3: Delivery & Logistics Management
-- Live GPS pings (target ~5 min interval) used for buyer/farmer live tracking,
-- ETA computation, and replaying a driver's path on past deliveries.
-- ============================================================

create table delivery_tracking (
  id              uuid primary key default gen_random_uuid(),
  delivery_id     uuid not null references delivery(id) on delete cascade,
  journey_id      uuid references journey(id),
  location_point  geography(Point, 4326) not null,
  speed_kmh       numeric,
  heading         numeric,
  recorded_at     timestamptz not null default now()
);

create index idx_delivery_tracking_delivery_time on delivery_tracking(delivery_id, recorded_at);
create index idx_delivery_tracking_point on delivery_tracking using gist (location_point);

alter table delivery_tracking enable row level security;

create policy "delivery_tracking_select_related" on delivery_tracking for select using (
  exists (
    select 1 from delivery d
    join orders o on o.id = d.order_id
    where d.id = delivery_tracking.delivery_id
      and (auth.uid() = o.buyer_profile_id or auth.uid() = o.farmer_profile_id)
  )
  or exists (
    select 1 from delivery_assignment da
    where da.delivery_id = delivery_tracking.delivery_id
      and da.driver_profile_id = auth.uid() and da.is_current
  )
);

create policy "delivery_tracking_insert_assigned_driver" on delivery_tracking for insert with check (
  exists (
    select 1 from delivery_assignment da
    where da.delivery_id = delivery_tracking.delivery_id
      and da.driver_profile_id = auth.uid() and da.is_current
  )
);

-- Straight-line ETA to the delivery's dropoff, using the driver's recent average
-- speed as a rough estimate.
create or replace function estimate_delivery_eta(p_delivery_id uuid)
returns timestamptz as $$
declare
  v_last        delivery_tracking;
  v_dropoff     geography;
  v_avg_speed   numeric;
  v_distance_m  numeric;
begin
  select * into v_last from delivery_tracking
  where delivery_id = p_delivery_id order by recorded_at desc limit 1;

  select dropoff_location_point into v_dropoff from delivery where id = p_delivery_id;

  if v_last.id is null or v_dropoff is null then
    return null;
  end if;

  select avg(speed_kmh) into v_avg_speed from delivery_tracking
  where delivery_id = p_delivery_id and speed_kmh is not null
    and recorded_at > now() - interval '30 minutes';

  v_avg_speed  := coalesce(v_avg_speed, 30); -- fallback assumption: 30 km/h
  v_distance_m := ST_Distance(v_last.location_point, v_dropoff);

  return v_last.recorded_at + make_interval(secs => (v_distance_m / 1000.0) / v_avg_speed * 3600);
end;
$$ language plpgsql stable security invoker;

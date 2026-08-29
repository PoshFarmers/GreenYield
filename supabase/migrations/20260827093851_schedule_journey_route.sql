-- ============================================================
-- MAIN COMPONENT 3: Delivery & Logistics Management (1 developer)
-- `driver_profile` and `vehicle` already exist from the shared Authentication &
-- Profiles migration (0001-0003). Architecture calls the vehicle table
-- `driver_vehicle`, but it is the SAME already-migrated `vehicle` table --
-- no duplicate table is created here, this component just builds on it.
-- ============================================================

create table driver_schedule (
  id                 uuid primary key default gen_random_uuid(),
  driver_profile_id  uuid not null references driver_profile(profile_id) on delete cascade,
  schedule_date      date not null,
  is_available       boolean not null default true,
  shift_start        time,
  shift_end          time,
  max_capacity_kg    numeric, -- optional override of vehicle.max_load_kg for that day
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  unique (driver_profile_id, schedule_date)
);

create trigger trg_driver_schedule_updated_at before update on driver_schedule for each row execute function set_updated_at();
create index idx_driver_schedule_date on driver_schedule(schedule_date);

create type journey_status as enum ('planned', 'in_progress', 'completed', 'cancelled');

create table journey (
  id                 uuid primary key default gen_random_uuid(),
  driver_profile_id  uuid not null references driver_profile(profile_id),
  vehicle_id         uuid not null references vehicle(id),
  journey_date       date not null,
  direction          text check (direction in ('outbound', 'return')),
  status             journey_status not null default 'planned',
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create index idx_journey_driver_date on journey(driver_profile_id, journey_date);
create trigger trg_journey_updated_at before update on journey for each row execute function set_updated_at();

create table route (
  id                          uuid primary key default gen_random_uuid(),
  journey_id                  uuid not null unique references journey(id) on delete cascade,
  estimated_distance_km       numeric,
  estimated_duration_minutes  int,
  created_at                  timestamptz not null default now()
);

create type stop_type as enum ('pickup', 'dropoff');

create table route_stop (
  id                  uuid primary key default gen_random_uuid(),
  route_id            uuid not null references route(id) on delete cascade,
  delivery_id         uuid, -- FK added in c3_02, once `delivery` exists
  stop_type           stop_type not null,
  sequence_number     int not null,
  location_text       text,
  location_point      geography(Point, 4326),
  planned_arrival_at  timestamptz,
  actual_arrival_at   timestamptz,
  created_at          timestamptz not null default now(),
  unique (route_id, sequence_number)
);

create index idx_route_stop_route on route_stop(route_id, sequence_number);

alter table driver_schedule enable row level security;
alter table journey enable row level security;
alter table route enable row level security;
alter table route_stop enable row level security;

create policy "driver_schedule_select_own" on driver_schedule for select using (auth.uid() = driver_profile_id);
create policy "driver_schedule_insert_own" on driver_schedule for insert with check (auth.uid() = driver_profile_id);
create policy "driver_schedule_update_own" on driver_schedule for update using (auth.uid() = driver_profile_id);
create policy "driver_schedule_delete_own" on driver_schedule for delete using (auth.uid() = driver_profile_id);

create policy "journey_select_own" on journey for select using (auth.uid() = driver_profile_id);
create policy "journey_update_own" on journey for update using (auth.uid() = driver_profile_id);
-- inserts are made by the trusted batching/assignment Edge Function (service role)

create policy "route_select_via_journey" on route for select using (
  exists (select 1 from journey j where j.id = route.journey_id and j.driver_profile_id = auth.uid())
);
create policy "route_stop_select_via_route" on route_stop for select using (
  exists (select 1 from route r join journey j on j.id = r.journey_id
          where r.id = route_stop.route_id and j.driver_profile_id = auth.uid())
);
create policy "route_stop_update_via_route" on route_stop for update using (
  exists (select 1 from route r join journey j on j.id = r.journey_id
          where r.id = route_stop.route_id and j.driver_profile_id = auth.uid())
);

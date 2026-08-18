create type vehicle_type as enum ('three_wheeler', 'van', 'lorry', 'truck', 'tractor');

create table driver_profile (
  profile_id  uuid primary key,
  role        user_role not null default 'driver' check (role = 'driver'),
  created_at  timestamptz not null default now(),
  foreign key (profile_id, role) references profile_role(profile_id, role) on delete cascade
);

create table vehicle (
  id                     uuid primary key default gen_random_uuid(),
  driver_profile_id      uuid not null references driver_profile(profile_id) on delete cascade,
  vehicle_type           vehicle_type not null,
  plate_number           text not null unique,
  max_load_kg            numeric not null check (max_load_kg > 0),
  preferred_min_load_kg  numeric check (preferred_min_load_kg is null or preferred_min_load_kg <= max_load_kg),
  details                jsonb not null default '{}',
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);

create index idx_vehicle_driver on vehicle(driver_profile_id);
create trigger trg_vehicle_updated_at before update on vehicle for each row execute function set_updated_at();

create table driver_route_preference (
  id                     uuid primary key default gen_random_uuid(),
  driver_profile_id      uuid not null references driver_profile(profile_id) on delete cascade,
  origin_location        text not null,
  destination_location   text not null,
  created_at             timestamptz not null default now()
);

create index idx_driver_route_pref_driver on driver_route_preference(driver_profile_id);

alter table driver_profile enable row level security;
alter table vehicle enable row level security;
alter table driver_route_preference enable row level security;

create policy "driver_profile_select_own" on driver_profile for select using (auth.uid() = profile_id);
create policy "driver_profile_insert_own" on driver_profile for insert with check (auth.uid() = profile_id);
create policy "driver_profile_update_own" on driver_profile for update using (auth.uid() = profile_id);

create policy "vehicle_select_own" on vehicle for select using (auth.uid() = driver_profile_id);
create policy "vehicle_insert_own" on vehicle for insert with check (auth.uid() = driver_profile_id);
create policy "vehicle_update_own" on vehicle for update using (auth.uid() = driver_profile_id);
create policy "vehicle_delete_own" on vehicle for delete using (auth.uid() = driver_profile_id);

create policy "driver_route_pref_select_own" on driver_route_preference for select using (auth.uid() = driver_profile_id);
create policy "driver_route_pref_insert_own" on driver_route_preference for insert with check (auth.uid() = driver_profile_id);
create policy "driver_route_pref_update_own" on driver_route_preference for update using (auth.uid() = driver_profile_id);
create policy "driver_route_pref_delete_own" on driver_route_preference for delete using (auth.uid() = driver_profile_id);
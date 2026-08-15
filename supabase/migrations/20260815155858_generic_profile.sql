-- ============================================================
-- GreenYield — 0001: generic profile only
-- Role-specific tables (profile_role, farmer/buyer/driver_profile)
-- are deferred to a later migration once those tickets are scoped.
-- ============================================================

create extension if not exists postgis;

-- Declared now even though profile_role/role tables don't exist yet —
-- profile.active_role needs the type, and extending an existing enum
-- later (alter type ... add value) is easy, so no harm in defining it early.
create type user_role as enum ('farmer', 'buyer', 'driver');

create type language_code as enum ('en', 'si', 'ta');

create type address_type as (
  line1        text,
  line2        text,
  city         text,
  postal_code  text
);

create table profile (
  id                  uuid primary key references auth.users(id) on delete cascade,
  first_name          text not null,
  last_name           text not null,
  address             address_type,
  phone               text,
  avatar_url          text,                  -- storage object path, e.g. 'avatars/<id>.jpg'
  preferred_language  language_code not null default 'en',
  active_role         user_role,             -- null until role tables/tickets exist
  location_text       text,
  location_point      geography(Point, 4326),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create index idx_profile_location_point on profile using gist (location_point);

create or replace function set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger trg_profile_updated_at
  before update on profile
  for each row execute function set_updated_at();

alter table profile enable row level security;

create policy "profile_select_own" on profile for select using (auth.uid() = id);
create policy "profile_insert_own" on profile for insert with check (auth.uid() = id);
create policy "profile_update_own" on profile for update using (auth.uid() = id);
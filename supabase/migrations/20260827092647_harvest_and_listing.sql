-- ============================================================
-- Produce & Marketplace Management
-- "What can I buy/sell, and how do I find it?"
--
-- `crop` and `crop_category`, since farmer_crop
-- needed the FK early. This component adds harvest + produce_listing
-- on top of that existing crop catalogue.
-- ============================================================

create table harvest (
  id                 uuid primary key default gen_random_uuid(),
  farmer_profile_id  uuid not null references farmer_profile(profile_id) on delete cascade,
  crop_id            uuid not null references crop(id),
  quantity_kg        numeric not null check (quantity_kg >= 0),
  harvested_on       date not null default current_date,
  created_at         timestamptz not null default now()
);

create index idx_harvest_farmer on harvest(farmer_profile_id);
create index idx_harvest_crop   on harvest(crop_id);

create type listing_status as enum ('active', 'sold_out', 'expired', 'flagged');

create table produce_listing (
  id                     uuid primary key default gen_random_uuid(),
  harvest_id             uuid not null references harvest(id) on delete cascade,
  farmer_profile_id      uuid not null references farmer_profile(profile_id) on delete cascade,
  crop_id                uuid not null references crop(id),
  price_per_kg           numeric not null check (price_per_kg >= 0),
  available_quantity_kg  numeric not null check (available_quantity_kg >= 0),
  status                 listing_status not null default 'active',
  published_at           timestamptz not null default now(),
  expires_at             timestamptz,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);

create index idx_listing_farmer on produce_listing(farmer_profile_id);
create index idx_listing_crop   on produce_listing(crop_id);
create index idx_listing_status on produce_listing(status);

create trigger trg_listing_updated_at
  before update on produce_listing
  for each row execute function set_updated_at();

alter table harvest enable row level security;
alter table produce_listing enable row level security;

create policy "harvest_select_own" on harvest for select using (auth.uid() = farmer_profile_id);
create policy "harvest_insert_own" on harvest for insert with check (auth.uid() = farmer_profile_id);
create policy "harvest_update_own" on harvest for update using (auth.uid() = farmer_profile_id);

create policy "listing_select_all"  on produce_listing for select using (true); -- browsable marketplace
create policy "listing_insert_own"  on produce_listing for insert with check (auth.uid() = farmer_profile_id);
create policy "listing_update_own"  on produce_listing for update using (auth.uid() = farmer_profile_id);
create policy "listing_delete_own"  on produce_listing for delete using (auth.uid() = farmer_profile_id);

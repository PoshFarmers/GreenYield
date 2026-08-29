-- ============================================================
-- Cart & Order Management
-- Templates that a scheduled Edge Function expands into concrete `orders` rows.
-- ============================================================

create type recurring_frequency as enum ('weekly', 'biweekly', 'monthly');
create type recurring_order_status as enum ('active', 'paused', 'cancelled');

create table recurring_order (
  id                 uuid primary key default gen_random_uuid(),
  buyer_profile_id   uuid not null references buyer_profile(profile_id) on delete cascade,
  farmer_profile_id  uuid not null references farmer_profile(profile_id),
  frequency          recurring_frequency not null,
  day_of_week        smallint check (day_of_week between 0 and 6), -- 0 = Sunday
  next_run_at        timestamptz not null,
  delivery_address   jsonb,
  delivery_location  geography(Point, 4326),
  status             recurring_order_status not null default 'active',
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create index idx_recurring_order_buyer     on recurring_order(buyer_profile_id);
create index idx_recurring_order_next_run  on recurring_order(next_run_at) where status = 'active';

create trigger trg_recurring_order_updated_at before update on recurring_order for each row execute function set_updated_at();

create table recurring_order_item (
  id                   uuid primary key default gen_random_uuid(),
  recurring_order_id   uuid not null references recurring_order(id) on delete cascade,
  crop_id              uuid not null references crop(id),
  quantity_kg          numeric not null check (quantity_kg > 0),
  created_at           timestamptz not null default now()
);

create index idx_recurring_order_item_order on recurring_order_item(recurring_order_id);

alter table recurring_order enable row level security;
alter table recurring_order_item enable row level security;

create policy "recurring_order_select_own" on recurring_order for select using (auth.uid() = buyer_profile_id);
create policy "recurring_order_insert_own" on recurring_order for insert with check (auth.uid() = buyer_profile_id);
create policy "recurring_order_update_own" on recurring_order for update using (auth.uid() = buyer_profile_id);
create policy "recurring_order_delete_own" on recurring_order for delete using (auth.uid() = buyer_profile_id);

create policy "recurring_order_item_select_own" on recurring_order_item for select using (
  exists (select 1 from recurring_order ro where ro.id = recurring_order_item.recurring_order_id and ro.buyer_profile_id = auth.uid())
);
create policy "recurring_order_item_insert_own" on recurring_order_item for insert with check (
  exists (select 1 from recurring_order ro where ro.id = recurring_order_item.recurring_order_id and ro.buyer_profile_id = auth.uid())
);
create policy "recurring_order_item_delete_own" on recurring_order_item for delete using (
  exists (select 1 from recurring_order ro where ro.id = recurring_order_item.recurring_order_id and ro.buyer_profile_id = auth.uid())
);

-- Scheduled (pg_cron / Edge Function) - materializes due recurring templates into
-- real orders. Left as a stub signature per the architecture's "contracts before
-- code" step -- Component 2's developer fills in the body against c2_02.
create or replace function generate_orders_from_recurring_templates()
returns int as $$
declare
  v_count int := 0;
begin
  -- For each due recurring_order: create one `orders` row (+ order_item rows priced
  -- against current produce_listing) per farmer represented in recurring_order_item,
  -- then advance next_run_at by `frequency`. Stubbed intentionally.
  return v_count;
end;
$$ language plpgsql security definer;

-- Scheduled/system-only: creates real orders on a buyer's behalf.
revoke execute on function generate_orders_from_recurring_templates() from public;
grant execute on function generate_orders_from_recurring_templates() to service_role;

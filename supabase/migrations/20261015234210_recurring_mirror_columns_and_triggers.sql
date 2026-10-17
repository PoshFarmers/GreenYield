-- ============================================================
-- Sync & Mirror Triggers for Recurring Orders & Recurring Schedule
-- ============================================================
-- 1. Ensure mirror columns exist on recurring_order
--    (frequency_text, status_text, delivery_location_geojson)
--    and establish BEFORE INSERT OR UPDATE trigger with backfill.
-- 2. Add mirror column status_text on recurring_schedule
--    and establish BEFORE INSERT OR UPDATE trigger with backfill.
-- 3. Ensure publication contains both tables.
-- ============================================================

-- Function: set_recurring_order_powersync_mirrors
create or replace function set_recurring_order_powersync_mirrors()
returns trigger as $$
begin
  new.frequency_text := new.frequency::text;
  new.status_text := new.status::text;
  new.delivery_location_geojson := case
    when new.delivery_location is null then null
    else ST_AsGeoJSON(new.delivery_location)
  end;
  return new;
end;
$$ language plpgsql;

-- Alter recurring_order and attach trigger
alter table recurring_order
  add column if not exists frequency_text text,
  add column if not exists status_text text,
  add column if not exists delivery_location_geojson text;

drop trigger if exists trg_recurring_order_powersync_mirrors on recurring_order;
create trigger trg_recurring_order_powersync_mirrors
  before insert or update of frequency, status, delivery_location on recurring_order
  for each row execute function set_recurring_order_powersync_mirrors();

-- Backfill recurring_order
update recurring_order
set frequency = frequency,
    status = status,
    delivery_location = delivery_location;

-- Function: set_recurring_schedule_powersync_mirrors
create or replace function set_recurring_schedule_powersync_mirrors()
returns trigger as $$
begin
  new.status_text := new.status::text;
  return new;
end;
$$ language plpgsql;

-- Alter recurring_schedule and attach trigger
alter table recurring_schedule
  add column if not exists status_text text;

drop trigger if exists trg_recurring_schedule_powersync_mirrors on recurring_schedule;
create trigger trg_recurring_schedule_powersync_mirrors
  before insert or update of status on recurring_schedule
  for each row execute function set_recurring_schedule_powersync_mirrors();

-- Backfill recurring_schedule
update recurring_schedule
set status = status;

-- Ensure tables in publication
do $$
begin
  if not exists (
    select 1 from pg_publication_tables 
    where pubname = 'powersync' and tablename = 'recurring_schedule'
  ) then
    alter publication powersync add table recurring_schedule;
  end if;

  if not exists (
    select 1 from pg_publication_tables 
    where pubname = 'powersync' and tablename = 'recurring_order'
  ) then
    alter publication powersync add table recurring_order;
  end if;

  if not exists (
    select 1 from pg_publication_tables 
    where pubname = 'powersync' and tablename = 'recurring_order_item'
  ) then
    alter publication powersync add table recurring_order_item;
  end if;
end;
$$;

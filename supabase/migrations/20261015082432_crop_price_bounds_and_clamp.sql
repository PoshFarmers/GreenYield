-- Task 12: server-driven price bounds on crop + CLAMPING triggers (never raise:
-- a raised error on a PowerSync-uploaded write would block the upload queue).

alter table crop
  add column if not exists price_floor_per_kg numeric
    check (price_floor_per_kg is null or price_floor_per_kg >= 0),
  add column if not exists price_ceiling_per_kg numeric
    check (price_ceiling_per_kg is null or price_ceiling_per_kg >= 0);

alter table crop drop constraint if exists crop_price_bounds_order;
alter table crop add constraint crop_price_bounds_order
  check (price_floor_per_kg is null or price_ceiling_per_kg is null
         or price_floor_per_kg <= price_ceiling_per_kg);

-- Seeded from lib/features/profile/farmer/crop_price_bounds.dart (corrected names).
update crop c
set price_floor_per_kg = s.lo, price_ceiling_per_kg = s.hi
from (values
  ('Tomato', 150, 250), ('Carrot', 120, 200), ('Cabbage', 80, 150),
  ('Eggplant', 100, 180), ('Okra', 150, 220), ('Pumpkin', 60, 120),
  ('Cucumber', 80, 150), ('Green Beans', 200, 300), ('Potato', 180, 280),
  ('Onion', 200, 320), ('Beetroot', 150, 220), ('Red bell pepper', 250, 400),
  ('Banana', 100, 180), ('Mango', 150, 350), ('Papaya', 80, 150),
  ('Pineapple', 100, 200), ('Watermelon', 60, 120), ('Orange', 150, 280),
  ('Guava', 120, 200), ('Jackfruit', 80, 150), ('Rambutan', 200, 350),
  ('Mangosteen', 400, 700)
) as s(name, lo, hi)
where c.name = s.name;

-- If the powersync publication uses a column list for crop, re-add it so the new
-- columns replicate (no-op otherwise).
do $$
begin
  if exists (
    select 1 from pg_publication_rel pr
    join pg_publication p on p.oid = pr.prpubid
    where p.pubname = 'powersync'
      and pr.prrelid = 'public.crop'::regclass
      and pr.prattrs is not null
  ) then
    alter publication powersync drop table public.crop;
    alter publication powersync add table public.crop;
  end if;
end;
$$;

create or replace function clamp_listing_price_to_bounds()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_lo numeric;
  v_hi numeric;
begin
  if new.price_per_kg is null then return new; end if;
  select price_floor_per_kg, price_ceiling_per_kg into v_lo, v_hi
  from crop where id = new.crop_id;
  if v_lo is not null and new.price_per_kg < v_lo then new.price_per_kg := v_lo; end if;
  if v_hi is not null and new.price_per_kg > v_hi then new.price_per_kg := v_hi; end if;
  return new;
end;
$$;

create or replace function clamp_farmer_crop_price_to_bounds()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_lo numeric;
  v_hi numeric;
begin
  if new.default_price_per_kg is null then return new; end if;
  select price_floor_per_kg, price_ceiling_per_kg into v_lo, v_hi
  from crop where id = new.crop_id;
  if v_lo is not null and new.default_price_per_kg < v_lo then new.default_price_per_kg := v_lo; end if;
  if v_hi is not null and new.default_price_per_kg > v_hi then new.default_price_per_kg := v_hi; end if;
  return new;
end;
$$;

revoke all on function clamp_listing_price_to_bounds() from public, anon, authenticated;
revoke all on function clamp_farmer_crop_price_to_bounds() from public, anon, authenticated;

-- "update of <price column>" only: checkout (stock/status updates) never triggers it.
drop trigger if exists trg_produce_listing_clamp_price on produce_listing;
create trigger trg_produce_listing_clamp_price
  before insert or update of price_per_kg on produce_listing
  for each row execute function clamp_listing_price_to_bounds();

drop trigger if exists trg_farmer_crop_clamp_price on farmer_crop;
create trigger trg_farmer_crop_clamp_price
  before insert or update of default_price_per_kg on farmer_crop
  for each row execute function clamp_farmer_crop_price_to_bounds();

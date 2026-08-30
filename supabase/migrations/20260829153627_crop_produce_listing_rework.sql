-- ============================================================
-- GreenYield -- migration: crop management + produce listing rework 
-- ============================================================


-- ------------------------------------------------------------
-- 1. farmer_crop: add description + default_price_per_kg
-- ------------------------------------------------------------

alter table farmer_crop
  add column if not exists description text;

alter table farmer_crop
  add column if not exists default_price_per_kg numeric
    check (default_price_per_kg is null or default_price_per_kg >= 0);

comment on column farmer_crop.description is
  'General description of how this farmer grows this crop (e.g. "Organic, chemical-free"). Shown on browse-by-farmer and as a fallback when a specific listing has no description of its own.';

comment on column farmer_crop.default_price_per_kg is
  'Farmer''s standing asking price for this crop, set at registration/profile-edit time. Pre-fills produce_listing.price_per_kg on creation; editable independently. Bounds enforced client-side in Flutter for now.';

-- Safe: appends description/default_price_per_kg after the existing
-- created_at column -- does not rename, reorder, or drop any existing
-- output column, so CREATE OR REPLACE VIEW is allowed here.
create or replace view farmer_crop_read
  with (security_invoker = true) as
select
  fc.farmer_profile_id,
  fc.crop_id,
  c.name                                       as crop_name,
  c.category                                   as crop_category,
  coalesce(fc.image_url, c.fallback_image_url) as display_image_url,
  fc.image_url                                 as farmer_image_url,
  c.fallback_image_url,
  fc.created_at,
  fc.description,
  fc.default_price_per_kg
from farmer_crop fc
join crop c on c.id = fc.crop_id;


-- ------------------------------------------------------------
-- 2. produce_listing: detach harvest_id, add the new listing-level fields
--    Must drop the FK + column BEFORE dropping harvest (section 3).
-- ------------------------------------------------------------

alter table produce_listing
  drop constraint if exists produce_listing_harvest_id_fkey;

alter table produce_listing
  drop column if exists harvest_id;

alter table produce_listing
  add column if not exists description text;   -- batch-specific note, e.g. "picked this morning, smaller batch".
                                                 -- Falls back to farmer_crop.description when null.

alter table produce_listing
  add column if not exists image_url text;      -- batch-specific photo override.
                                                 -- Falls back to farmer_crop.image_url, then crop.fallback_image_url.

alter table produce_listing
  add column if not exists harvested_on date;   -- optional, informational only -- no longer a separate table/FK

comment on column produce_listing.harvested_on is
  'Optional, informational only. Previously tracked via a separate harvest table (now dropped) with its own FK; that table added no capability the app was using, so the date moved here directly.';


-- ------------------------------------------------------------
-- 3. Drop harvest
--    Safe now that produce_listing no longer references it.
--    SAFETY: if harvest has rows you care about, uncomment the backup
--    line below before running this against an environment with real data.
-- ------------------------------------------------------------

-- create table harvest_backup_pre_drop as table harvest;

drop table if exists harvest;


-- ------------------------------------------------------------
-- 4. marketplace_listing_read: fold in the listing-level overrides,
--    KEEPING the existing crop_image_url column name/position, and
--    APPENDING description + harvested_on at the end.
-- ------------------------------------------------------------

create or replace view marketplace_listing_read
  with (security_invoker = true) as
select
  pl.id,
  pl.farmer_profile_id,
  p.first_name || ' ' || p.last_name                        as farmer_name,
  pl.crop_id,
  c.name                                                     as crop_name,
  c.category                                                 as crop_category,
  coalesce(pl.image_url, fc.image_url, c.fallback_image_url) as crop_image_url, -- name unchanged; expression now includes the listing-level override
  pl.price_per_kg,
  pl.available_quantity_kg,
  pl.status,
  p.location_text                                            as farmer_location_text,
  p.location_point                                           as farmer_location_point,
  pl.published_at,
  pl.expires_at,
  coalesce(pl.description, fc.description)                   as description,
  pl.harvested_on
from produce_listing pl
join crop c on c.id = pl.crop_id
join profile p on p.id = pl.farmer_profile_id
left join farmer_crop fc on fc.farmer_profile_id = pl.farmer_profile_id and fc.crop_id = pl.crop_id
where pl.status = 'active';

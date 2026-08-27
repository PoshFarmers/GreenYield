-- ============================================================
-- GENERAL COMPONENT: 3.1 Authentication, Registration & Profiles
-- ALTERATION to the already-migrated schema 
--
-- Architecture change vs. what was already migrated:
--   - crop.fallback_image_url : default image shown for a crop when the
--                                farmer hasn't uploaded their own photo.
--   - farmer_crop.image_url   : the farmer's own photo for that crop.
--     (farmer_crop is the already-migrated table that corresponds to
--      "crops_grown" in the architecture doc -- no new table, just new columns.)
-- ============================================================

alter table crop
  add column if not exists fallback_image_url text;

comment on column crop.fallback_image_url is
  'Default image shown for this crop when a farmer has not set their own photo in farmer_crop.image_url.';

alter table farmer_crop
  add column if not exists image_url text;

comment on column farmer_crop.image_url is
  'Farmer-uploaded photo (storage object path) for this specific crop. Falls back to crop.fallback_image_url when null.';

-- Convenience read view so clients don't have to implement the fallback logic themselves.
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
  fc.created_at
from farmer_crop fc
join crop c on c.id = fc.crop_id;

grant select on farmer_crop_read to authenticated;
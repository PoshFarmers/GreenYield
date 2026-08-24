-- ============================================================
-- GreenYield — address column: composite type -> jsonb
-- Composite Postgres types don't reliably replicate through
-- PowerSync, and were awkward to bind from the local SQLite side.
--
-- profile_read depends on `address`, so it has to be dropped before
-- the column type can change, then recreated afterward.
-- ============================================================

drop view if exists profile_read;

alter table profile
  alter column address type jsonb
  using (
    case
      when address is null then null
      else jsonb_strip_nulls(jsonb_build_object(
        'line1', (address).line1,
        'line2', (address).line2,
        'city', (address).city,
        'postal_code', (address).postal_code
      ))
    end
  );

drop type if exists address_type cascade;

create view profile_read
  with (security_invoker = true) as
select
  id,
  first_name,
  last_name,
  address,
  phone,
  avatar_url,
  preferred_language,
  active_role,
  location_text,
  case
    when location_point is null then null
    else ST_AsEWKT(location_point)
  end as location_point,
  created_at,
  updated_at
from profile;

grant select on profile_read to authenticated;
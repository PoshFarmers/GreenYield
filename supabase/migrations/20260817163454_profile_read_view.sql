-- ============================================================
-- GreenYield — 0003: profile_read view (GeoJSON for location_point)
-- PostgREST returns geography columns as WKB hex by default, not
-- GeoJSON. This view exposes location_point as GeoJSON so the
-- Flutter client's GeoPoint.fromGeoJson() can parse it.
-- ============================================================

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
    else ST_AsGeoJSON(location_point)::json
  end as location_point,
  created_at,
  updated_at
from profile;

grant select on profile_read to authenticated;
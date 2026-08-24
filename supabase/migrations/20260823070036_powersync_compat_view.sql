-- PowerSync's Postgres replication works most reliably against plain
-- scalar types. These plain columns mirror the enum/geography columns
-- as text/json for the sync publication:
--   active_role       (enum user_role)      -> active_role_text
--   preferred_language (enum language_code) -> preferred_language_text
--   location_point    (geography Point)     -> location_geojson
--
-- Both enum::text casts (via enum_out, which is STABLE not IMMUTABLE)
-- and ST_AsGeoJSON (also STABLE) are disallowed in GENERATED ... STORED
-- columns, so a trigger maintains these instead.

alter table profile
  add column active_role_text text,
  add column preferred_language_text text,
  add column location_geojson text;

create or replace function set_profile_powersync_mirrors()
returns trigger as $$
begin
  new.active_role_text := new.active_role::text;
  new.preferred_language_text := new.preferred_language::text;
  new.location_geojson :=
    case when new.location_point is null then null
         else ST_AsGeoJSON(new.location_point)
    end;
  return new;
end;
$$ language plpgsql;

create trigger trg_profile_powersync_mirrors
  before insert or update of active_role, preferred_language, location_point on profile
  for each row execute function set_profile_powersync_mirrors();

-- Backfill existing rows. Must reassign the exact columns the trigger
-- watches (active_role, preferred_language, location_point) — an
-- `OF column_list` trigger only fires when those columns appear in the
-- UPDATE's SET clause, regardless of whether the value actually changes.
-- Updating an unrelated column (e.g. `id`) will NOT fire it.
update profile
set active_role = active_role,
    preferred_language = preferred_language,
    location_point = location_point;
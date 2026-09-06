-- ============================================================
-- Structured location persistence for driver_route_preference.
--
-- origin_location / destination_location already hold the
-- human-readable address string. This migration adds the
-- coordinates + place id alongside them so a selected point can be
-- reused elsewhere in the app (map previews, distance/duration
-- estimates, re-centering a picker, etc.) without re-geocoding the
-- address string every time.
-- ============================================================

alter table driver_route_preference
  add column origin_lat            double precision,
  add column origin_lng            double precision,
  add column origin_place_id       text,
  add column destination_lat       double precision,
  add column destination_lng       double precision,
  add column destination_place_id  text,
  add column distance_km           numeric,
  add column duration_minutes      int;

comment on column driver_route_preference.origin_lat is
  'Latitude of origin_location, when resolved via geocoding/places.';
comment on column driver_route_preference.destination_lat is
  'Latitude of destination_location, when resolved via geocoding/places.';
comment on column driver_route_preference.distance_km is
  'Cached route distance for the last-matched corridor, shown on the route-selection UI.';

create type route_direction as enum ('outbound', 'return', 'both');

alter table driver_route_preference
  add column direction    route_direction not null default 'both',
  add column active_days  smallint not null default 0, -- bitmask: bit0=Mon ... bit6=Sun
  add column is_active    boolean not null default true;

comment on column driver_route_preference.active_days is
  'Bitmask of recurring days, bit 0 = Monday .. bit 6 = Sunday. 0 = no recurring day selected (route may still be used ad-hoc).';

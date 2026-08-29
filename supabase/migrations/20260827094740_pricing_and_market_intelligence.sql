-- ============================================================
-- Delivery pricing rules + market price analytics.
-- ============================================================

create table pricing_rule (
  id              uuid primary key default gen_random_uuid(),
  name            text not null,
  base_fee        numeric not null default 0 check (base_fee >= 0),
  per_km_rate     numeric not null default 0 check (per_km_rate >= 0),
  min_fee         numeric,
  max_fee         numeric,
  effective_from  timestamptz not null default now(),
  effective_to    timestamptz,
  is_active       boolean not null default true,
  created_at      timestamptz not null default now()
);

create index idx_pricing_rule_active on pricing_rule(is_active) where is_active;

create table price_history (
  id                uuid primary key default gen_random_uuid(),
  crop_id           uuid not null references crop(id),
  price_date        date not null,
  avg_price_per_kg  numeric not null,
  min_price_per_kg  numeric not null,
  max_price_per_kg  numeric not null,
  order_count       int not null default 0,
  created_at        timestamptz not null default now(),
  unique (crop_id, price_date)
);

create index idx_price_history_crop_date on price_history(crop_id, price_date);

create table market_price (
  crop_id           uuid primary key references crop(id),
  avg_price_per_kg  numeric,
  min_price_per_kg  numeric,
  max_price_per_kg  numeric,
  as_of_date        date,
  updated_at        timestamptz not null default now()
);

create table price_trend (
  crop_id          uuid primary key references crop(id),
  trend_direction  text check (trend_direction in ('up', 'down', 'stable')),
  change_percent   numeric,
  period_days      int not null default 7,
  computed_at      timestamptz not null default now()
);

alter table pricing_rule enable row level security;
alter table price_history enable row level security;
alter table market_price enable row level security;
alter table price_trend enable row level security;

create policy "pricing_rule_select_all"  on pricing_rule  for select using (true);
create policy "price_history_select_all" on price_history for select using (true);
create policy "market_price_select_all"  on market_price  for select using (true);
create policy "price_trend_select_all"   on price_trend   for select using (true);
-- all four are backend-maintained reference data; no client-facing insert/update policies

-- Called by Component 2 at checkout -- the location-based delivery fee, computed
-- here so the pricing logic is never duplicated in Order Management.
create or replace function calculate_delivery_fee(
  p_pickup   geography,
  p_dropoff  geography
)
returns numeric as $$
declare
  v_rule  pricing_rule;
  v_km    numeric;
  v_fee   numeric;
begin
  select * into v_rule from pricing_rule
  where is_active = true and effective_from <= now() and (effective_to is null or effective_to > now())
  order by effective_from desc limit 1;

  if v_rule.id is null then
    return 0;
  end if;

  v_km  := ST_Distance(p_pickup, p_dropoff) / 1000.0;
  v_fee := v_rule.base_fee + (v_km * v_rule.per_km_rate);

  if v_rule.min_fee is not null and v_fee < v_rule.min_fee then v_fee := v_rule.min_fee; end if;
  if v_rule.max_fee is not null and v_fee > v_rule.max_fee then v_fee := v_rule.max_fee; end if;

  return round(v_fee, 2);
end;
$$ language plpgsql stable;

-- Scheduled aggregation (pg_cron / Edge Function) -- rebuilds price_history/
-- market_price/price_trend from completed orders (reads Component 2's tables).
create or replace function refresh_market_price_analytics(p_for_date date default current_date)
returns void as $$
begin
  insert into price_history (crop_id, price_date, avg_price_per_kg, min_price_per_kg, max_price_per_kg, order_count)
  select oi.crop_id, p_for_date, avg(oi.price_per_kg), min(oi.price_per_kg), max(oi.price_per_kg), count(*)
  from order_item oi
  join orders o on o.id = oi.order_id
  where o.status = 'completed' and o.placed_at::date = p_for_date
  group by oi.crop_id
  on conflict (crop_id, price_date) do update
    set avg_price_per_kg = excluded.avg_price_per_kg,
        min_price_per_kg = excluded.min_price_per_kg,
        max_price_per_kg = excluded.max_price_per_kg,
        order_count = excluded.order_count;

  insert into market_price (crop_id, avg_price_per_kg, min_price_per_kg, max_price_per_kg, as_of_date, updated_at)
  select crop_id, avg_price_per_kg, min_price_per_kg, max_price_per_kg, price_date, now()
  from price_history where price_date = p_for_date
  on conflict (crop_id) do update
    set avg_price_per_kg = excluded.avg_price_per_kg,
        min_price_per_kg = excluded.min_price_per_kg,
        max_price_per_kg = excluded.max_price_per_kg,
        as_of_date = excluded.as_of_date,
        updated_at = now();

  insert into price_trend (crop_id, trend_direction, change_percent, period_days, computed_at)
  select
    curr.crop_id,
    case when curr.avg_price_per_kg > prev.avg_price_per_kg then 'up'
         when curr.avg_price_per_kg < prev.avg_price_per_kg then 'down'
         else 'stable' end,
    round(((curr.avg_price_per_kg - prev.avg_price_per_kg) / nullif(prev.avg_price_per_kg, 0)) * 100, 2),
    7,
    now()
  from price_history curr
  join price_history prev on prev.crop_id = curr.crop_id and prev.price_date = curr.price_date - 7
  where curr.price_date = p_for_date
  on conflict (crop_id) do update
    set trend_direction = excluded.trend_direction,
        change_percent = excluded.change_percent,
        computed_at = now();
end;
$$ language plpgsql;

-- calculate_delivery_fee is read-only/stateless (no security definer, runs
-- as invoker) and safe to expose so the client can preview delivery cost.
grant execute on function calculate_delivery_fee(geography, geography) to authenticated;

-- refresh_market_price_analytics rebuilds reference-data tables from all
-- completed orders across the platform -- scheduled job only.
revoke execute on function refresh_market_price_analytics(date) from public;
grant execute on function refresh_market_price_analytics(date) to service_role;

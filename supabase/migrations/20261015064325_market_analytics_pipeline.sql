-- Task 7: market analytics pipeline correctness.
do $$
begin
  if to_regclass('public.platform_config') is null then
    raise exception 'Task 4 migration missing: platform_config';
  end if;
end;
$$;

-- ------------------------------------------------------------
-- Columns
-- ------------------------------------------------------------
alter table price_history
  add column if not exists total_quantity_kg numeric not null default 0 check (total_quantity_kg >= 0),
  add column if not exists is_synthetic boolean not null default false;

-- Existing seed rows (order_count = 0) are synthetic. Rows written by the old
-- refresh (completed orders, placed_at date, unweighted) are dropped and rebuilt
-- below with the new logic.
update price_history set is_synthetic = true where order_count = 0;
delete from price_history where order_count > 0;

alter table market_price
  add column if not exists sample_size int not null default 0 check (sample_size >= 0),
  add column if not exists source text not null default 'seed' check (source in ('orders', 'seed'));

insert into platform_config (key, value) values ('market_min_sample_orders', 3)
on conflict (key) do nothing;

-- ------------------------------------------------------------
-- PowerSync publication: if the powersync publication uses column lists for
-- these tables, the new columns would not replicate. Re-add them (no column
-- list = all columns). No-op when there is no column list.
-- ------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array['market_price', 'price_history'] loop
    if exists (
      select 1
      from pg_publication_rel pr
      join pg_publication p on p.oid = pr.prpubid
      where p.pubname = 'powersync'
        and pr.prrelid = ('public.' || t)::regclass
        and pr.prattrs is not null
    ) then
      execute format('alter publication powersync drop table public.%I', t);
      execute format('alter publication powersync add table public.%I', t);
    end if;
  end loop;
end;
$$;

-- ------------------------------------------------------------
-- refresh_market_price_analytics(date): ONE signature (old one dropped).
--  1. price_history for the date: delivered + completed orders, date from the
--     delivered timestamp (fallback placed_at) in Asia/Colombo, quantity-weighted
--     average, distinct order count. Real rows overwrite synthetic ones.
--  2. market_price: rolling 14-day weighted window ending at the date, real data
--     only; skipped (row kept) when the sample is below market_min_sample_orders.
--  3. price_trend: last 7 days vs previous 7 days, real data only; 'stable' with
--     null change when either window has no orders.
-- Steps 2-3 are skipped when the date is older than the newest real day, so
-- re-running an old date never regresses current values.
-- ------------------------------------------------------------
drop function if exists refresh_market_price_analytics(date);

create function refresh_market_price_analytics(p_for_date date default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_date       date := coalesce(p_for_date, (now() at time zone 'Asia/Colombo')::date);
  v_min_sample int  := coalesce((select value from platform_config where key = 'market_min_sample_orders'), 3)::int;
  v_latest     date;
begin
  insert into price_history (
    crop_id, price_date, avg_price_per_kg, min_price_per_kg, max_price_per_kg,
    order_count, total_quantity_kg, is_synthetic
  )
  select oi.crop_id, v_date,
         round(sum(oi.line_total) / sum(oi.quantity_kg), 2),
         min(oi.price_per_kg), max(oi.price_per_kg),
         count(distinct oi.order_id)::int, sum(oi.quantity_kg), false
  from order_item oi
  join orders o on o.id = oi.order_id
  where o.status in ('delivered', 'completed')
    and (coalesce(
           (select max(h.changed_at) from order_status_history h
            where h.order_id = o.id and h.status = 'delivered'),
           o.placed_at
         ) at time zone 'Asia/Colombo')::date = v_date
  group by oi.crop_id
  on conflict (crop_id, price_date) do update
    set avg_price_per_kg  = excluded.avg_price_per_kg,
        min_price_per_kg  = excluded.min_price_per_kg,
        max_price_per_kg  = excluded.max_price_per_kg,
        order_count       = excluded.order_count,
        total_quantity_kg = excluded.total_quantity_kg,
        is_synthetic      = false;

  select max(price_date) into v_latest from price_history where not is_synthetic;
  if v_latest is not null and v_date < v_latest then
    return;
  end if;

  insert into market_price (
    crop_id, avg_price_per_kg, min_price_per_kg, max_price_per_kg,
    as_of_date, updated_at, sample_size, source
  )
  select w.crop_id, round(w.val / w.qty, 2), w.mn, w.mx, v_date, now(), w.n, 'orders'
  from (
    select crop_id,
           sum(avg_price_per_kg * total_quantity_kg) as val,
           sum(total_quantity_kg) as qty,
           min(min_price_per_kg) as mn,
           max(max_price_per_kg) as mx,
           sum(order_count)::int as n
    from price_history
    where not is_synthetic and price_date between v_date - 13 and v_date
    group by crop_id
  ) w
  where w.qty > 0 and w.n >= v_min_sample
  on conflict (crop_id) do update
    set avg_price_per_kg = excluded.avg_price_per_kg,
        min_price_per_kg = excluded.min_price_per_kg,
        max_price_per_kg = excluded.max_price_per_kg,
        as_of_date       = excluded.as_of_date,
        sample_size      = excluded.sample_size,
        source           = 'orders',
        updated_at       = now();

  insert into price_trend (crop_id, trend_direction, change_percent, period_days, computed_at)
  select c.id,
         case when t.pct is null then 'stable'
              when t.pct > 1 then 'up'
              when t.pct < -1 then 'down'
              else 'stable' end,
         t.pct, 7, now()
  from crop c
  left join (
    select s.crop_id,
           case when coalesce(s.cur_qty, 0) > 0 and coalesce(s.prev_qty, 0) > 0
                then round(
                  ((s.cur_val / s.cur_qty) - (s.prev_val / s.prev_qty))
                  / nullif(s.prev_val / s.prev_qty, 0) * 100, 2)
           end as pct
    from (
      select crop_id,
             sum(avg_price_per_kg * total_quantity_kg) filter (where price_date >= v_date - 6) as cur_val,
             sum(total_quantity_kg)                    filter (where price_date >= v_date - 6) as cur_qty,
             sum(avg_price_per_kg * total_quantity_kg) filter (where price_date <= v_date - 7) as prev_val,
             sum(total_quantity_kg)                    filter (where price_date <= v_date - 7) as prev_qty
      from price_history
      where not is_synthetic and price_date between v_date - 13 and v_date
      group by crop_id
    ) s
  ) t on t.crop_id = c.id
  on conflict (crop_id) do update
    set trend_direction = excluded.trend_direction,
        change_percent  = excluded.change_percent,
        period_days     = 7,
        computed_at     = now();
end;
$$;

create function backfill_market_price_analytics(p_from date, p_to date)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  d date;
  n int := 0;
begin
  if p_from is null or p_to is null or p_from > p_to then
    raise exception 'invalid_date_range' using errcode = '22023';
  end if;
  if p_to - p_from > 366 then
    raise exception 'date_range_too_large' using errcode = '22023';
  end if;
  for d in select generate_series(p_from, p_to, interval '1 day')::date loop
    perform refresh_market_price_analytics(d);
    n := n + 1;
  end loop;
  return n;
end;
$$;

revoke all on function refresh_market_price_analytics(date) from public, anon, authenticated;
revoke all on function backfill_market_price_analytics(date, date) from public, anon, authenticated;
grant execute on function refresh_market_price_analytics(date) to service_role;
grant execute on function backfill_market_price_analytics(date, date) to service_role;

-- ------------------------------------------------------------
-- Cron: pg_cron runs in UTC; Colombo midnight is 18:30 UTC, so 19:00 UTC =
-- 00:30 Colombo. Refreshes Colombo-yesterday (late deliveries) and today.
-- ------------------------------------------------------------
do $$
begin
  if to_regnamespace('cron') is null then
    raise warning 'pg_cron is not installed: schedule the nightly analytics job manually';
    return;
  end if;
  if exists (select 1 from cron.job where jobname = 'refresh_market_price_analytics_nightly') then
    perform cron.unschedule('refresh_market_price_analytics_nightly');
  end if;
  perform cron.schedule(
    'refresh_market_price_analytics_nightly',
    '0 19 * * *',
    $cmd$select public.backfill_market_price_analytics(
           (now() at time zone 'Asia/Colombo')::date - 1,
           (now() at time zone 'Asia/Colombo')::date)$cmd$
  );
end;
$$;

-- ------------------------------------------------------------
-- One-off rebuild from the first delivered order (or just reset trends).
-- ------------------------------------------------------------
do $$
declare
  v_from  date;
  v_today date := (now() at time zone 'Asia/Colombo')::date;
begin
  select min((coalesce(
           (select max(h.changed_at) from order_status_history h
            where h.order_id = o.id and h.status = 'delivered'),
           o.placed_at) at time zone 'Asia/Colombo')::date)
  into v_from
  from orders o
  where o.status in ('delivered', 'completed');

  if v_from is null then
    perform refresh_market_price_analytics(v_today);
  else
    perform backfill_market_price_analytics(greatest(v_from, v_today - 365), v_today);
  end if;
end;
$$;

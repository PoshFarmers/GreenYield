-- ============================================================
-- Dev-only seed: backfill 30 days of price_history per crop.
-- CropPriceHistorySection needs >=2 rows per crop to render a line;
-- the real pipeline (refresh_market_price_analytics -> nightly cron)
-- can't populate this yet because no order has reached 'completed'.
-- This is throwaway data — once completions exist and the cron job
-- starts writing real rows, it will simply overwrite these by date
-- (unique on crop_id, price_date) and you can eventually delete
-- whatever's left of this synthetic range.
-- ============================================================

insert into price_history (
  crop_id, price_date, avg_price_per_kg, min_price_per_kg, max_price_per_kg, order_count
)
select
  mp.crop_id,
  d.day::date as price_date,
  round(
    (
      (mp.min_price_per_kg + mp.max_price_per_kg) / 2.0
        + ((mp.max_price_per_kg - mp.min_price_per_kg) / 2.0)
          * sin((d.day::date - (current_date - 29)) * 0.35
                + (hashtext(mp.crop_id::text) % 100) / 15.0)
    )::numeric,
    2
  ) as avg_price_per_kg,
  mp.min_price_per_kg,
  mp.max_price_per_kg,
  0 as order_count
from market_price mp
cross join generate_series(current_date - 29, current_date, interval '1 day') as d(day)
where mp.avg_price_per_kg is not null
on conflict (crop_id, price_date) do update
  set avg_price_per_kg = excluded.avg_price_per_kg,
      min_price_per_kg = excluded.min_price_per_kg,
      max_price_per_kg = excluded.max_price_per_kg;

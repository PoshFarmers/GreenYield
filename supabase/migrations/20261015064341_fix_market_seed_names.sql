-- The 20260831200556 seed used Brinjal/Capsicum; the crop catalogue names are
-- Eggplant/Red bell pepper. Insert only what is missing (no-op if rows exist).
insert into market_price (crop_id, avg_price_per_kg, min_price_per_kg, max_price_per_kg, as_of_date, updated_at, source)
select c.id, s.avg, s.min, s.max, current_date, now(), 'seed'
from crop c
join (values
  ('Eggplant',        140, 100, 180),
  ('Red bell pepper', 325, 250, 400)
) as s(name, avg, min, max) on c.name = s.name
on conflict (crop_id) do nothing;

insert into price_trend (crop_id, trend_direction, change_percent, period_days, computed_at)
select c.id, 'stable', null, 7, now()
from crop c
on conflict (crop_id) do nothing;

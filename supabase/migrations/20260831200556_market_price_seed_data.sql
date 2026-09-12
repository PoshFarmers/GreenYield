-- ------------------------------------------------------------
-- market_price: one row per crop, avg/min/max = crop_price_bounds
-- midpoint/min/max from the Flutter client.
-- ------------------------------------------------------------

insert into market_price (crop_id, avg_price_per_kg, min_price_per_kg, max_price_per_kg, as_of_date, updated_at)
select c.id, seed.avg, seed.min, seed.max, current_date, now()
from crop c
join (values
  ('Tomato',        200, 150, 250),
  ('Carrot',        160, 120, 200),
  ('Cabbage',        115,  80, 150),
  ('Brinjal',        140, 100, 180),
  ('Okra',           185, 150, 220),
  ('Pumpkin',         90,  60, 120),
  ('Cucumber',       115,  80, 150),
  ('Green Beans',    250, 200, 300),
  ('Potato',         230, 180, 280),
  ('Onion',          260, 200, 320),
  ('Beetroot',       185, 150, 220),
  ('Capsicum',       325, 250, 400),
  ('Banana',         140, 100, 180),
  ('Mango',          250, 150, 350),
  ('Papaya',         115,  80, 150),
  ('Pineapple',      150, 100, 200),
  ('Watermelon',      90,  60, 120),
  ('Orange',         215, 150, 280),
  ('Guava',          160, 120, 200),
  ('Jackfruit',      115,  80, 150),
  ('Rambutan',       275, 200, 350),
  ('Mangosteen',     550, 400, 700)
) as seed(name, avg, min, max) on c.name = seed.name
on conflict (crop_id) do update
  set avg_price_per_kg = excluded.avg_price_per_kg,
      min_price_per_kg = excluded.min_price_per_kg,
      max_price_per_kg = excluded.max_price_per_kg,
      as_of_date = excluded.as_of_date,
      updated_at = now();

-- ------------------------------------------------------------
-- price_trend: alternating up/down/stable across crops, purely for
-- demo variety — real trend computation reads two price_history
-- rows 7 days apart, which seed data has no real history to derive
-- from yet.
-- ------------------------------------------------------------

insert into price_trend (crop_id, trend_direction, change_percent, period_days, computed_at)
select c.id, seed.direction, seed.change_percent, 7, now()
from crop c
join (values
  ('Tomato',       'up',      6.5),
  ('Carrot',       'stable',  0.8),
  ('Cabbage',      'down',   -4.2),
  ('Brinjal',      'up',      3.1),
  ('Okra',         'stable',  0.0),
  ('Pumpkin',      'down',   -5.0),
  ('Cucumber',     'up',      2.4),
  ('Green Beans',  'up',      8.0),
  ('Potato',       'stable',  1.2),
  ('Onion',        'down',   -3.6),
  ('Beetroot',     'up',      4.4),
  ('Capsicum',     'up',      7.2),
  ('Banana',       'stable',  0.5),
  ('Mango',        'down',   -6.1),
  ('Papaya',       'up',      2.9),
  ('Pineapple',    'stable',  1.0),
  ('Watermelon',   'down',   -2.3),
  ('Orange',       'up',      3.8),
  ('Guava',        'stable',  0.2),
  ('Jackfruit',    'down',   -1.9),
  ('Rambutan',     'up',      5.6),
  ('Mangosteen',   'stable',  0.7)
) as seed(name, direction, change_percent) on c.name = seed.name
on conflict (crop_id) do update
  set trend_direction = excluded.trend_direction,
      change_percent = excluded.change_percent,
      computed_at = now();

-- ------------------------------------------------------------
-- price_history: one row for today per crop, so price_history_recent
-- (already a live PowerSync stream) has something to sync. order_count
-- is 0 since these are seeded, not derived from real orders.
-- ------------------------------------------------------------

insert into price_history (crop_id, price_date, avg_price_per_kg, min_price_per_kg, max_price_per_kg, order_count)
select mp.crop_id, current_date, mp.avg_price_per_kg, mp.min_price_per_kg, mp.max_price_per_kg, 0
from market_price mp
on conflict (crop_id, price_date) do update
  set avg_price_per_kg = excluded.avg_price_per_kg,
      min_price_per_kg = excluded.min_price_per_kg,
      max_price_per_kg = excluded.max_price_per_kg;
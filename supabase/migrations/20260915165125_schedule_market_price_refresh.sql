-- ============================================================
-- refresh_market_price_analytics() gets called periodically
-- ============================================================

create extension if not exists pg_cron;

select cron.schedule(
  'refresh_market_price_analytics_nightly',
  '0 1 * * *',
  $$select refresh_market_price_analytics();$$
);

-- ============================================================
-- Seed the default delivery pricing rule.
--
-- Idempotent: only inserts when no active rule exists, so a
-- re-run (or an environment where someone already added one by
-- hand) is a no-op rather than a duplicate.
-- ============================================================

insert into pricing_rule (
  name, base_fee, per_km_rate, min_fee, max_fee, effective_from, is_active
)
select
  'Standard delivery', 150, 25, 150, 2000, now() - interval '1 day', true
where not exists (
  select 1 from pricing_rule
  where is_active
    and effective_from <= now()
    and (effective_to is null or effective_to > now())
);
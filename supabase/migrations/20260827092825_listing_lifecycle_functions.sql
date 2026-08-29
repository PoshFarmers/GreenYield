-- ============================================================
-- Produce & Marketplace Management
-- Lifecycle functions: atomic stock decrement (called cross-component by
-- Component 2 at checkout via RPC) and scheduled auto-expiry of stale listings.
-- ============================================================

-- Atomic, race-safe decrement so two buyers can't oversell the same stock.
create or replace function decrement_listing_quantity(
  p_listing_id  uuid,
  p_quantity_kg numeric
)
returns produce_listing as $$
declare
  v_listing produce_listing;
begin
  update produce_listing
  set available_quantity_kg = available_quantity_kg - p_quantity_kg,
      status = case when available_quantity_kg - p_quantity_kg <= 0 then 'sold_out' else status end,
      updated_at = now()
  where id = p_listing_id
    and available_quantity_kg >= p_quantity_kg
    and status = 'active'
  returning * into v_listing;

  if v_listing.id is null then
    raise exception 'Insufficient stock or listing not active for listing %', p_listing_id
      using errcode = 'P0001';
  end if;

  return v_listing;
end;
$$ language plpgsql security definer;

-- Reverses a decrement (e.g. order cancelled before pickup) - called by Component 2.
create or replace function restock_listing_quantity(
  p_listing_id  uuid,
  p_quantity_kg numeric
)
returns produce_listing as $$
declare
  v_listing produce_listing;
begin
  update produce_listing
  set available_quantity_kg = available_quantity_kg + p_quantity_kg,
      status = case when status = 'sold_out' then 'active' else status end,
      updated_at = now()
  where id = p_listing_id
  returning * into v_listing;

  return v_listing;
end;
$$ language plpgsql security definer;

-- Scheduled (pg_cron / Edge Function cron) - flips stale listings to expired.
create or replace function expire_stale_listings()
returns void as $$
  update produce_listing
  set status = 'expired', updated_at = now()
  where status = 'active'
    and expires_at is not null
    and expires_at < now();
$$ language sql;

-- All three mutate stock/listing state outside of any RLS-checkable ownership
-- rule (decrement/restock don't even take a farmer id) -- must be backend-only.
revoke execute on function decrement_listing_quantity(uuid, numeric) from public;
grant execute on function decrement_listing_quantity(uuid, numeric) to service_role;

revoke execute on function restock_listing_quantity(uuid, numeric) from public;
grant execute on function restock_listing_quantity(uuid, numeric) to service_role;

revoke execute on function expire_stale_listings() from public;
grant execute on function expire_stale_listings() to service_role;

-- ============================================================
-- Farmer-side stock edits on an existing listing.
--
-- Why an RPC and not a plain PowerSync UPDATE of available_quantity_kg:
--   * Checkout decrements stock server-side. A client-written absolute
--     value ("set stock to 40") read before a sale and uploaded after it
--     would silently overwrite that sale and oversell. A *delta* applied
--     atomically here can't.
--   * Restocking a sold-out listing has to flip `status` back to
--     'active' (and emptying it to 'sold_out'). `status` is an enum the
--     client can't safely write (see the powersync_compat_view notes);
--     doing it here keeps the enum and its status_text mirror in step
--     via the existing trigger.
--
-- Unlike PowerSync-uploaded writes (which must never raise, or they
-- block the upload queue — see crop_price_bounds_and_clamp), this is a
-- direct RPC, so raising a clear error is the right behaviour.
-- ============================================================

create or replace function adjust_own_listing_stock(
  p_listing_id uuid,
  p_delta_kg   numeric
)
returns numeric
language plpgsql
security definer
set search_path = public
as $$
declare
  v_listing produce_listing;
begin
  if p_delta_kg is null or p_delta_kg = 0 then
    raise exception 'Stock change must be non-zero' using errcode = '22023';
  end if;

  update produce_listing
  set available_quantity_kg = greatest(0, available_quantity_kg + p_delta_kg),
      status = case
        when greatest(0, available_quantity_kg + p_delta_kg) = 0
             and status = 'active' then 'sold_out'::listing_status
        when greatest(0, available_quantity_kg + p_delta_kg) > 0
             and status = 'sold_out' then 'active'::listing_status
        else status
      end,
      updated_at = now()
  where id = p_listing_id
    and farmer_profile_id = auth.uid()
    -- Expired/flagged listings aren't the farmer's to revive this way.
    and status in ('active', 'sold_out')
  returning * into v_listing;

  if v_listing.id is null then
    raise exception 'Listing not found, not yours, or no longer editable'
      using errcode = 'P0002';
  end if;

  return v_listing.available_quantity_kg;
end;
$$;

revoke all on function adjust_own_listing_stock(uuid, numeric) from public, anon;
grant execute on function adjust_own_listing_stock(uuid, numeric) to authenticated;

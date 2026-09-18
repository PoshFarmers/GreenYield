-- ============================================================
-- Per-batch listing breakdown for one farmer/crop pair, shown when a
-- buyer taps a crop tile on the farmer's public profile
-- (get_farmer_public_profile only returns the *aggregate* available
-- stock per crop, not the individual batches behind it).
--
-- There's no stored "initial quantity" for a batch — harvest was
-- dropped (see the crop_produce_listing_rework migration) and
-- produce_listing.available_quantity_kg is decremented in place by
-- checkout (see checkout_transaction and later fixes). The only thing
-- that ever reduces it is a sold order_item, so the initial amount is
-- reconstructed as available_quantity_kg + sum(order_item.quantity_kg)
-- for that listing.
--
-- SECURITY DEFINER for the same reason as get_farmer_public_profile:
-- produce_listing RLS already allows anyone to select (browsable
-- marketplace), but this keeps the same access pattern/shape as the
-- rest of the public-profile RPCs.
-- ============================================================

create or replace function get_farmer_crop_listings(p_farmer_id uuid, p_crop_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id',                    pl.id,
      'available_quantity_kg', pl.available_quantity_kg,
      'initial_quantity_kg',   pl.available_quantity_kg + coalesce(sold.sold_kg, 0),
      'status',                pl.status::text,
      'harvested_on',          pl.harvested_on,
      'published_at',          pl.published_at,
      'price_per_kg',          pl.price_per_kg,
      -- Per-batch overrides only; the client falls back to the
      -- farmer_crop/crop values it already has from the public profile.
      'description',           pl.description,
      'listing_image_url',     pl.image_url
    )
    -- Buyable batches first, then newest harvest.
    order by (pl.status = 'active' and pl.available_quantity_kg > 0) desc,
             coalesce(pl.harvested_on::timestamptz, pl.published_at) desc
  ), '[]'::jsonb)
  from produce_listing pl
  left join (
    select produce_listing_id, sum(quantity_kg) as sold_kg
    from order_item
    group by produce_listing_id
  ) sold on sold.produce_listing_id = pl.id
  where pl.farmer_profile_id = p_farmer_id and pl.crop_id = p_crop_id;
$$;

revoke all on function get_farmer_crop_listings(uuid, uuid) from public, anon;
grant execute on function get_farmer_crop_listings(uuid, uuid) to authenticated;

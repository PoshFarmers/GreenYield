-- ============================================================
-- Public farmer profile for buyers: name/avatar/location (from
-- `profile`, which RLS otherwise restricts to own-row reads — see
-- get_order_detail for the same problem on orders), crops grown with
-- currently-available stock (farmer_crop joined to active
-- produce_listing), the rating aggregate, and the review list.
--
-- SECURITY DEFINER so it can read across profile rows, same pattern as
-- get_order_detail / search_marketplace_listings. No caller-identity
-- check beyond auth.uid() being set (any authenticated user, i.e. any
-- buyer or farmer, may look up any farmer's public profile) — nothing
-- returned here is more sensitive than what the marketplace RPCs
-- already expose (no phone, no exact address).
-- ============================================================

create or replace function get_farmer_public_profile(p_farmer_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_profile profile;
  v_farmer  farmer_profile;
  v_crops   jsonb;
  v_reviews jsonb;
begin
  select * into v_farmer from farmer_profile where profile_id = p_farmer_id;
  if v_farmer.profile_id is null then
    return null;
  end if;

  select * into v_profile from profile where id = p_farmer_id;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'crop_id',                 c.id,
      'crop_name',                c.name,
      'crop_category',            c.category::text,
      'description',              fc.description,
      'farmer_crop_image_url',    fc.image_url,
      'crop_fallback_image_url',  c.fallback_image_url,
      'default_price_per_kg',     fc.default_price_per_kg,
      'available_quantity_kg',    coalesce(stock.total_kg, 0)
    )
    order by c.name
  ), '[]'::jsonb)
  into v_crops
  from farmer_crop fc
  join crop c on c.id = fc.crop_id
  left join (
    select crop_id, sum(available_quantity_kg) as total_kg
    from produce_listing
    where farmer_profile_id = p_farmer_id and status = 'active'
    group by crop_id
  ) stock on stock.crop_id = fc.crop_id
  where fc.farmer_profile_id = p_farmer_id;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id',         r.id,
      'rating',     r.rating,
      'comment',    r.comment,
      'created_at', r.created_at,
      'buyer_name', trim(coalesce(bp.first_name, '') || ' ' || coalesce(bp.last_name, ''))
    )
    order by r.created_at desc
  ), '[]'::jsonb)
  into v_reviews
  from farmer_review r
  join profile bp on bp.id = r.buyer_profile_id
  where r.farmer_profile_id = p_farmer_id;

  return jsonb_build_object(
    'farmer_profile_id',    p_farmer_id,
    'farmer_name',           trim(coalesce(v_profile.first_name, '') || ' ' || coalesce(v_profile.last_name, '')),
    'farmer_avatar_url',     v_profile.avatar_url,
    'farmer_location_text',  v_profile.location_text,
    'avg_rating',            v_farmer.avg_rating,
    'review_count',          v_farmer.review_count,
    'crops',                 v_crops,
    'reviews',               v_reviews
  );
end;
$$;

revoke all on function get_farmer_public_profile(uuid) from public, anon;
grant execute on function get_farmer_public_profile(uuid) to authenticated;

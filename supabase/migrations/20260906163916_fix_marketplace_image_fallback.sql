-- ============================================================
-- GreenYield -- fix marketplace fallback image not resolving
--
-- search_marketplace_listings / get_marketplace_listing pre-coalesced
-- the image chain into one `image_url` column:
--     coalesce(pl.image_url, fc.image_url, c.fallback_image_url)
-- but each tier lives in a DIFFERENT storage bucket -- pl.image_url and
-- fc.image_url are in the private 'crop-photos' bucket, while
-- c.fallback_image_url is in the public 'crop-fallback-images' bucket
-- (see ProduceListing.displayImage / FarmerCrop.displayImage, which
-- both keep the tiers separate for exactly this reason). The client
-- always requested the coalesced path from 'crop-photos', so whenever a
-- listing actually fell back to the crop's catalogue image, the signed-
-- URL lookup missed (wrong bucket) and only the placeholder ever showed.
--
-- Fix: return the three tiers separately, like produce_listing_read
-- already does, and let the client pick bucket/visibility itself via a
-- displayImage getter (see MarketplaceListing).
-- ============================================================

drop function if exists search_marketplace_listings(
  text, crop_category, uuid, double precision, double precision, int, int
);

create function search_marketplace_listings(
  p_query       text default null,
  p_category    crop_category default null,
  p_farmer_id   uuid default null,
  p_buyer_lat   double precision default null,
  p_buyer_lng   double precision default null,
  p_limit       int default 20,
  p_offset      int default 0
)
returns table (
  id                       uuid,
  farmer_profile_id        uuid,
  farmer_name              text,
  farmer_avatar_url        text,
  farmer_location_text     text,
  crop_id                  uuid,
  crop_name                text,
  crop_category            text,
  listing_image_url        text,
  farmer_crop_image_url    text,
  crop_fallback_image_url  text,
  description              text,
  price_per_kg             numeric,
  available_quantity_kg    numeric,
  harvested_on             date,
  published_at             timestamptz,
  distance_km              double precision
)
language sql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
  -- pg_trgm's own setter, rather than `set pg_trgm.similarity_threshold =
  -- 0.25` as a function option: the migration role doesn't have
  -- permission to SET that custom extension GUC directly (42501), but
  -- calling the extension's own function to change it is unrestricted.
  select set_limit(0.25);

  select
    pl.id,
    pl.farmer_profile_id,
    p.first_name || ' ' || p.last_name                          as farmer_name,
    p.avatar_url                                                as farmer_avatar_url,
    p.location_text                                             as farmer_location_text,
    pl.crop_id,
    c.name                                                      as crop_name,
    c.category::text                                            as crop_category,
    pl.image_url                                                as listing_image_url,
    fc.image_url                                                as farmer_crop_image_url,
    c.fallback_image_url                                        as crop_fallback_image_url,
    coalesce(pl.description, fc.description)                    as description,
    pl.price_per_kg,
    pl.available_quantity_kg,
    pl.harvested_on,
    pl.published_at,
    case
      when p_buyer_lat is null or p_buyer_lng is null or p.location_point is null
        then null
      else ST_Distance(
             p.location_point,
             ST_SetSRID(ST_MakePoint(p_buyer_lng, p_buyer_lat), 4326)::geography
           ) / 1000.0
    end                                                         as distance_km
  from produce_listing pl
  join crop c    on c.id = pl.crop_id
  join profile p on p.id = pl.farmer_profile_id
  left join farmer_crop fc
    on fc.farmer_profile_id = pl.farmer_profile_id
   and fc.crop_id = pl.crop_id
  where pl.status = 'active'
    and pl.available_quantity_kg > 0
    and (p_category  is null or c.category = p_category)
    and (p_farmer_id is null or pl.farmer_profile_id = p_farmer_id)
    and (
      p_query is null
      or btrim(p_query) = ''
      or c.name % p_query
      or c.name ilike '%' || p_query || '%'
      or (p.first_name || ' ' || p.last_name) ilike '%' || p_query || '%'
      or p.location_text ilike '%' || p_query || '%'
    )
  -- A SQL function's ORDER BY can't reference an output alias, so the
  -- distance expression is repeated here rather than reusing distance_km.
  order by
    case
      when p_query is null or btrim(p_query) = '' then null
      else similarity(c.name, p_query)
    end desc nulls last,
    case
      when p_buyer_lat is null or p_buyer_lng is null or p.location_point is null
        then null
      else ST_Distance(
             p.location_point,
             ST_SetSRID(ST_MakePoint(p_buyer_lng, p_buyer_lat), 4326)::geography
           )
    end asc nulls last,
    pl.published_at desc,
    pl.id
  limit  greatest(p_limit, 0)
  offset greatest(p_offset, 0);
$$;

revoke execute on function search_marketplace_listings(
  text, crop_category, uuid, double precision, double precision, int, int
) from public;

grant execute on function search_marketplace_listings(
  text, crop_category, uuid, double precision, double precision, int, int
) to authenticated;


drop function if exists get_marketplace_listing(uuid, double precision, double precision);

create function get_marketplace_listing(
  p_listing_id  uuid,
  p_buyer_lat   double precision default null,
  p_buyer_lng   double precision default null
)
returns table (
  id                       uuid,
  farmer_profile_id        uuid,
  farmer_name              text,
  farmer_avatar_url        text,
  farmer_location_text     text,
  crop_id                  uuid,
  crop_name                text,
  crop_category            text,
  listing_image_url        text,
  farmer_crop_image_url    text,
  crop_fallback_image_url  text,
  description              text,
  price_per_kg             numeric,
  available_quantity_kg    numeric,
  harvested_on             date,
  published_at             timestamptz,
  distance_km              double precision
)
language sql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
  select
    pl.id,
    pl.farmer_profile_id,
    p.first_name || ' ' || p.last_name,
    p.avatar_url,
    p.location_text,
    pl.crop_id,
    c.name,
    c.category::text,
    pl.image_url,
    fc.image_url,
    c.fallback_image_url,
    coalesce(pl.description, fc.description),
    pl.price_per_kg,
    pl.available_quantity_kg,
    pl.harvested_on,
    pl.published_at,
    case
      when p_buyer_lat is null or p_buyer_lng is null or p.location_point is null
        then null
      else ST_Distance(
             p.location_point,
             ST_SetSRID(ST_MakePoint(p_buyer_lng, p_buyer_lat), 4326)::geography
           ) / 1000.0
    end
  from produce_listing pl
  join crop c    on c.id = pl.crop_id
  join profile p on p.id = pl.farmer_profile_id
  left join farmer_crop fc
    on fc.farmer_profile_id = pl.farmer_profile_id
   and fc.crop_id = pl.crop_id
  where pl.id = p_listing_id;
$$;

revoke execute on function get_marketplace_listing(uuid, double precision, double precision)
  from public;

grant execute on function get_marketplace_listing(uuid, double precision, double precision)
  to authenticated;

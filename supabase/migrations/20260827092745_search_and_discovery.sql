-- ============================================================
-- Produce & Marketplace Management
-- Search & discovery: trigram search on crop name, plus a buyer-facing
-- read view that joins listing + crop + farmer for browsing/maps.
-- ============================================================

create extension if not exists pg_trgm;

create index idx_crop_name_trgm on crop using gin (name gin_trgm_ops);

create view marketplace_listing_read
  with (security_invoker = true) as
select
  pl.id,
  pl.farmer_profile_id,
  p.first_name || ' ' || p.last_name              as farmer_name,
  pl.crop_id,
  c.name                                           as crop_name,
  c.category                                       as crop_category,
  coalesce(fc.image_url, c.fallback_image_url)     as crop_image_url,
  pl.price_per_kg,
  pl.available_quantity_kg,
  pl.status,
  p.location_text                                  as farmer_location_text,
  p.location_point                                  as farmer_location_point,
  pl.published_at,
  pl.expires_at
from produce_listing pl
join crop c on c.id = pl.crop_id
join profile p on p.id = pl.farmer_profile_id
left join farmer_crop fc on fc.farmer_profile_id = pl.farmer_profile_id and fc.crop_id = pl.crop_id
where pl.status = 'active';

grant select on marketplace_listing_read to authenticated;

-- Typo-tolerant crop-name search, optionally ordered by distance from the buyer.
create or replace function search_produce_listings(
  p_query        text default null,
  p_buyer_lat    double precision default null,
  p_buyer_lng    double precision default null,
  p_max_results  int default 50
)
returns setof marketplace_listing_read as $$
  select *
  from marketplace_listing_read
  where p_query is null or crop_name % p_query
  order by
    case when p_buyer_lat is not null and p_buyer_lng is not null
      then ST_Distance(farmer_location_point, ST_SetSRID(ST_MakePoint(p_buyer_lng, p_buyer_lat), 4326)::geography)
      else null
    end asc nulls last,
    published_at desc
  limit p_max_results;
$$ language sql stable security invoker;

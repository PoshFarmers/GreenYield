-- ============================================================
-- GreenYield -- buyer marketplace access
--
-- Buyers can read produce_listing (listing_select_all), but `profile`
-- and `farmer_crop` are own-row-only under RLS. marketplace_listing_read
-- is security_invoker and INNER JOINs profile, so it returns zero rows
-- for a buyer. The pre-existing search_produce_listings has the same
-- problem and was never granted to anyone.
--
-- Rather than opening `profile` up wholesale (which would expose phone
-- and address app-wide), this adds SECURITY DEFINER functions that
-- return an explicit, marketplace-safe column list -- and only for
-- farmers who actually have an active listing.
--
-- marketplace_listing_read and search_produce_listings are deliberately
-- left untouched: the latter declares `returns setof
-- marketplace_listing_read`, so reshaping the view would break it.
-- ============================================================


-- ------------------------------------------------------------
-- 1. Indexes for the new search paths.
--    crop.name already has idx_crop_name_trgm; produce_listing.status
--    already has idx_listing_status.
-- ------------------------------------------------------------

create index if not exists idx_profile_name_trgm
  on profile using gin ((first_name || ' ' || last_name) gin_trgm_ops);

create index if not exists idx_profile_location_text_trgm
  on profile using gin (location_text gin_trgm_ops);

-- Serves the default "browse, newest first" feed, which is the common case.
create index if not exists idx_listing_active_published
  on produce_listing (published_at desc)
  where status = 'active';


-- ------------------------------------------------------------
-- 2. search_marketplace_listings
--
--    Typo-tolerant across crop name, and substring across crop name,
--    farmer name and farmer location. Ordered by name similarity when
--    there's a query, then by distance, then newest.
--
--    distance_km is computed rather than returning location_point --
--    PostgREST serialises geography as WKB hex, which the Flutter
--    client can't parse (this is why profile_read exists separately).
-- ------------------------------------------------------------

create or replace function search_marketplace_listings(
  p_query       text default null,
  p_category    crop_category default null,
  p_farmer_id   uuid default null,
  p_buyer_lat   double precision default null,
  p_buyer_lng   double precision default null,
  p_limit       int default 20,
  p_offset      int default 0
)
returns table (
  id                     uuid,
  farmer_profile_id      uuid,
  farmer_name            text,
  farmer_avatar_url      text,
  farmer_location_text   text,
  crop_id                uuid,
  crop_name              text,
  crop_category          text,
  image_url              text,
  description            text,
  price_per_kg           numeric,
  available_quantity_kg  numeric,
  harvested_on           date,
  published_at           timestamptz,
  distance_km            double precision
)
language sql
stable
security definer
set search_path = public, extensions, pg_temp
set pg_trgm.similarity_threshold = 0.25
as $$
  select
    pl.id,
    pl.farmer_profile_id,
    p.first_name || ' ' || p.last_name                          as farmer_name,
    p.avatar_url                                                as farmer_avatar_url,
    p.location_text                                             as farmer_location_text,
    pl.crop_id,
    c.name                                                      as crop_name,
    c.category::text                                            as crop_category,
    coalesce(pl.image_url, fc.image_url, c.fallback_image_url)   as image_url,
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


-- ------------------------------------------------------------
-- 3. get_marketplace_listing -- one listing for the detail screen.
--    Same shape as the search, so the client reuses one model.
--    Not restricted to active listings: a buyer may have the detail
--    screen open when the stock sells out, and showing the row with
--    zero stock beats a blank screen.
-- ------------------------------------------------------------

create or replace function get_marketplace_listing(
  p_listing_id  uuid,
  p_buyer_lat   double precision default null,
  p_buyer_lng   double precision default null
)
returns table (
  id                     uuid,
  farmer_profile_id      uuid,
  farmer_name            text,
  farmer_avatar_url      text,
  farmer_location_text   text,
  crop_id                uuid,
  crop_name              text,
  crop_category          text,
  image_url              text,
  description            text,
  price_per_kg           numeric,
  available_quantity_kg  numeric,
  harvested_on           date,
  published_at           timestamptz,
  distance_km            double precision
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
    coalesce(pl.image_url, fc.image_url, c.fallback_image_url),
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


-- ------------------------------------------------------------
-- 4. list_marketplace_farmers -- the discovery row.
--    Only farmers with at least one active, in-stock listing.
-- ------------------------------------------------------------

create or replace function list_marketplace_farmers(
  p_buyer_lat  double precision default null,
  p_buyer_lng  double precision default null,
  p_limit      int default 10
)
returns table (
  farmer_profile_id     uuid,
  farmer_name           text,
  farmer_avatar_url     text,
  farmer_location_text  text,
  crop_names            text[],
  listing_count         bigint,
  distance_km           double precision
)
language sql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
  select
    p.id,
    p.first_name || ' ' || p.last_name,
    p.avatar_url,
    p.location_text,
    array_agg(distinct c.name order by c.name),
    count(distinct pl.id),
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
  where pl.status = 'active'
    and pl.available_quantity_kg > 0
  group by p.id, p.first_name, p.last_name, p.avatar_url,
           p.location_text, p.location_point
  order by
    case
      when p_buyer_lat is null or p_buyer_lng is null or p.location_point is null
        then null
      else ST_Distance(
             p.location_point,
             ST_SetSRID(ST_MakePoint(p_buyer_lng, p_buyer_lat), 4326)::geography
           )
    end asc nulls last,
    count(distinct pl.id) desc
  limit greatest(p_limit, 0);
$$;

revoke execute on function list_marketplace_farmers(double precision, double precision, int)
  from public;

grant execute on function list_marketplace_farmers(double precision, double precision, int)
  to authenticated;


-- ------------------------------------------------------------
-- 5. Storage: let signed-in users READ marketplace images.
--
--    Both buckets stay private and write access stays owner-only --
--    these add select alongside the existing own-folder policies, so
--    the client keeps fetching via signed URLs (see MediaCache).
--
--    Trade-off: any authenticated user can read any avatar or crop
--    photo if they know the object path. Accepted because a buyer must
--    see a farmer's produce photo and face to shop. Making the buckets
--    public would be strictly worse -- it removes auth entirely.
-- ------------------------------------------------------------

drop policy if exists "crop_photo_select_authenticated" on storage.objects;
create policy "crop_photo_select_authenticated"
  on storage.objects for select
  to authenticated
  using (bucket_id = 'crop-photos');

drop policy if exists "avatar_select_authenticated" on storage.objects;
create policy "avatar_select_authenticated"
  on storage.objects for select
  to authenticated
  using (bucket_id = 'avatars');

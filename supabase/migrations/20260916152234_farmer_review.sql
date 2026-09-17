-- farmer_review: one row per delivered order, buyer -> farmer rating/comment.
-- Reviews are optional and editable (upsert keyed on order_id).
create table farmer_review (
  id                 uuid primary key default gen_random_uuid(),
  order_id           uuid not null unique references orders(id) on delete cascade,
  buyer_profile_id   uuid not null references buyer_profile(profile_id) on delete cascade,
  farmer_profile_id  uuid not null references farmer_profile(profile_id) on delete cascade,
  rating             smallint not null check (rating between 1 and 5),
  comment            text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create index idx_farmer_review_farmer on farmer_review(farmer_profile_id, created_at desc);
create index idx_farmer_review_buyer on farmer_review(buyer_profile_id);

create trigger trg_farmer_review_updated_at
  before update on farmer_review
  for each row execute function set_updated_at();

alter table farmer_review enable row level security;

-- Reviews are public read (shown on the farmer's profile to any buyer browsing).
create policy "farmer_review_select_public" on farmer_review
  for select using (true);

-- No insert/update/delete policy: all writes go through submit_farmer_review()
-- below, which enforces "caller is the order's buyer and the order is delivered".

-- Aggregate columns on farmer_profile, trigger-maintained.
alter table farmer_profile
  add column avg_rating numeric(3, 2) not null default 0,
  add column review_count integer not null default 0;

create or replace function refresh_farmer_rating_aggregate(p_farmer_profile_id uuid)
returns void as $$
  perform 1
  from farmer_profile
  where profile_id = p_farmer_profile_id
  for update;

  update farmer_profile fp
  set avg_rating = coalesce(
        (select round(avg(rating)::numeric, 2) from farmer_review where farmer_profile_id = p_farmer_profile_id), 0),
      review_count = (select count(*) from farmer_review where farmer_profile_id = p_farmer_profile_id)
  where fp.profile_id = p_farmer_profile_id;
end;
$$ language plpgsql;

create or replace function trg_farmer_review_aggregate()
returns trigger as $$
begin
  if tg_op = 'DELETE' then
    perform refresh_farmer_rating_aggregate(old.farmer_profile_id);
    return old;
  end if;
  perform refresh_farmer_rating_aggregate(new.farmer_profile_id);
  return new;
end;
$$ language plpgsql;

create trigger trg_farmer_review_aggregate_iud
  after insert or update of rating or delete on farmer_review
  for each row execute function trg_farmer_review_aggregate();

-- Client entry point: validates + upserts (create-or-edit) a review.
create or replace function submit_farmer_review(
  p_order_id uuid,
  p_rating smallint,
  p_comment text
)
returns farmer_review as $$
declare
  v_order orders%rowtype;
  v_review farmer_review%rowtype;
begin
  if p_rating < 1 or p_rating > 5 then
    raise exception 'rating must be between 1 and 5';
  end if;

  select * into v_order from orders where id = p_order_id;
  if v_order.id is null then
    raise exception 'order not found';
  end if;
  if auth.uid() <> v_order.buyer_profile_id then
    raise exception 'not authorized to review this order';
  end if;
  if v_order.status <> 'delivered' then
    raise exception 'order is not yet delivered';
  end if;

  insert into farmer_review (order_id, buyer_profile_id, farmer_profile_id, rating, comment)
  values (p_order_id, v_order.buyer_profile_id, v_order.farmer_profile_id, p_rating, p_comment)
  on conflict (order_id) do update
    set rating = excluded.rating, comment = excluded.comment, updated_at = now()
  returning * into v_review;

  return v_review;
end;
$$ language plpgsql security definer set search_path = public;

revoke all on function submit_farmer_review(uuid, smallint, text) from public, anon;
grant execute on function submit_farmer_review(uuid, smallint, text) to authenticated;

-- Replicate the new table to buyers/farmers via PowerSync.
alter publication powersync add table farmer_review;

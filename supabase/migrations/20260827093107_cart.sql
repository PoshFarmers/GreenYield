-- ============================================================
-- Cart & Order Management
-- Depends on produce_listing.
-- ============================================================

create table cart (
  id                uuid primary key default gen_random_uuid(),
  buyer_profile_id  uuid not null unique references buyer_profile(profile_id) on delete cascade,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create trigger trg_cart_updated_at before update on cart for each row execute function set_updated_at();

create table cart_item (
  id                  uuid primary key default gen_random_uuid(),
  cart_id             uuid not null references cart(id) on delete cascade,
  produce_listing_id  uuid not null references produce_listing(id) on delete cascade,
  quantity_kg         numeric not null check (quantity_kg > 0),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  unique (cart_id, produce_listing_id)
);

create trigger trg_cart_item_updated_at before update on cart_item for each row execute function set_updated_at();
create index idx_cart_item_cart on cart_item(cart_id);

alter table cart enable row level security;
alter table cart_item enable row level security;

create policy "cart_select_own" on cart for select using (auth.uid() = buyer_profile_id);
create policy "cart_insert_own" on cart for insert with check (auth.uid() = buyer_profile_id);
create policy "cart_update_own" on cart for update using (auth.uid() = buyer_profile_id);

create policy "cart_item_select_own" on cart_item for select using (
  exists (select 1 from cart where cart.id = cart_item.cart_id and cart.buyer_profile_id = auth.uid())
);
create policy "cart_item_insert_own" on cart_item for insert with check (
  exists (select 1 from cart where cart.id = cart_item.cart_id and cart.buyer_profile_id = auth.uid())
);
create policy "cart_item_update_own" on cart_item for update using (
  exists (select 1 from cart where cart.id = cart_item.cart_id and cart.buyer_profile_id = auth.uid())
);
create policy "cart_item_delete_own" on cart_item for delete using (
  exists (select 1 from cart where cart.id = cart_item.cart_id and cart.buyer_profile_id = auth.uid())
);

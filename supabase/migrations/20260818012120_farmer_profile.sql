create type crop_category as enum ('vegetable', 'fruit');

create table crop (
  id          uuid primary key default gen_random_uuid(),
  name        text not null unique,
  category    crop_category not null,
  created_at  timestamptz not null default now()
);

create table farmer_profile (
  profile_id  uuid primary key,
  role        user_role not null default 'farmer' check (role = 'farmer'),
  created_at  timestamptz not null default now(),
  foreign key (profile_id, role) references profile_role(profile_id, role) on delete cascade
);

create table farmer_crop (
  farmer_profile_id  uuid not null references farmer_profile(profile_id) on delete cascade,
  crop_id            uuid not null references crop(id) on delete restrict,
  created_at         timestamptz not null default now(),
  primary key (farmer_profile_id, crop_id)
);

create index idx_farmer_crop_crop on farmer_crop(crop_id);

alter table farmer_profile enable row level security;
alter table crop enable row level security;
alter table farmer_crop enable row level security;

create policy "farmer_profile_select_own" on farmer_profile for select using (auth.uid() = profile_id);
create policy "farmer_profile_insert_own" on farmer_profile for insert with check (auth.uid() = profile_id);
create policy "farmer_profile_update_own" on farmer_profile for update using (auth.uid() = profile_id);

create policy "crop_select_all" on crop for select using (true);

create policy "farmer_crop_select_own" on farmer_crop for select using (auth.uid() = farmer_profile_id);
create policy "farmer_crop_insert_own" on farmer_crop for insert with check (auth.uid() = farmer_profile_id);
create policy "farmer_crop_delete_own" on farmer_crop for delete using (auth.uid() = farmer_profile_id);

insert into crop (name, category) values
  ('Tomato', 'vegetable'), ('Carrot', 'vegetable'), ('Cabbage', 'vegetable'),
  ('Brinjal', 'vegetable'), ('Okra', 'vegetable'), ('Pumpkin', 'vegetable'),
  ('Cucumber', 'vegetable'), ('Green Beans', 'vegetable'), ('Potato', 'vegetable'),
  ('Onion', 'vegetable'), ('Beetroot', 'vegetable'), ('Capsicum', 'vegetable'),
  ('Banana', 'fruit'), ('Mango', 'fruit'), ('Papaya', 'fruit'),
  ('Pineapple', 'fruit'), ('Watermelon', 'fruit'), ('Orange', 'fruit'),
  ('Guava', 'fruit'), ('Jackfruit', 'fruit'), ('Rambutan', 'fruit'), ('Mangosteen', 'fruit')
on conflict (name) do nothing;
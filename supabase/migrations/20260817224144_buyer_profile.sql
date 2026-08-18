create type buyer_type as enum ('individual', 'organization');

create table buyer_profile (
  profile_id   uuid primary key,
  role         user_role not null default 'buyer' check (role = 'buyer'),
  buyer_type   buyer_type not null default 'individual',
  buyer_label  text,
  created_at   timestamptz not null default now(),
  foreign key (profile_id, role) references profile_role(profile_id, role) on delete cascade,
  check (buyer_type = 'individual' or buyer_label is not null)
);

alter table buyer_profile enable row level security;

create policy "buyer_profile_select_own" on buyer_profile for select using (auth.uid() = profile_id);
create policy "buyer_profile_insert_own" on buyer_profile for insert with check (auth.uid() = profile_id);
create policy "buyer_profile_update_own" on buyer_profile for update using (auth.uid() = profile_id);
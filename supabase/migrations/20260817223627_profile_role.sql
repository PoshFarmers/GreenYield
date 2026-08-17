-- ============================================================
-- GreenYield — profile_role junction table
-- Foundation for role-specific profiles. Must be applied before
-- any role-specific migration below, since their tables FK-
-- reference this one.
-- ============================================================

create table profile_role (
  id          uuid primary key default gen_random_uuid(),
  profile_id  uuid not null references profile(id) on delete cascade,
  role        user_role not null,
  created_at  timestamptz not null default now(),
  unique (profile_id, role)
);

create index idx_profile_role_profile on profile_role(profile_id);

alter table profile_role enable row level security;

create policy "profile_role_select_own" on profile_role for select using (auth.uid() = profile_id);
create policy "profile_role_insert_own" on profile_role for insert with check (auth.uid() = profile_id);
create policy "profile_role_delete_own" on profile_role for delete using (auth.uid() = profile_id);
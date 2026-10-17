-- ============================================================
-- Update Recurring Orders Schema
-- ============================================================

alter table orders add column source text not null default 'manual' check (source in ('manual', 'recurring'));

create table recurring_schedule (
  id                 uuid primary key default gen_random_uuid(),
  buyer_profile_id   uuid not null references buyer_profile(profile_id) on delete cascade,
  label              text not null,
  status             recurring_order_status not null default 'active',
  created_at         timestamptz not null default now()
);

create index idx_recurring_schedule_buyer on recurring_schedule(buyer_profile_id);

alter table recurring_schedule enable row level security;
create policy "recurring_schedule_select_own" on recurring_schedule for select using (auth.uid() = buyer_profile_id);
create policy "recurring_schedule_insert_own" on recurring_schedule for insert with check (auth.uid() = buyer_profile_id);
create policy "recurring_schedule_update_own" on recurring_schedule for update using (auth.uid() = buyer_profile_id);
create policy "recurring_schedule_delete_own" on recurring_schedule for delete using (auth.uid() = buyer_profile_id);

-- Alter existing recurring_order
-- 1. Drop existing policies
drop policy "recurring_order_select_own" on recurring_order;
drop policy "recurring_order_insert_own" on recurring_order;
drop policy "recurring_order_update_own" on recurring_order;
drop policy "recurring_order_delete_own" on recurring_order;

drop policy "recurring_order_item_select_own" on recurring_order_item;
drop policy "recurring_order_item_insert_own" on recurring_order_item;
drop policy "recurring_order_item_delete_own" on recurring_order_item;

-- 2. Modify columns
-- Because the table is empty (it was a stub), we can just clear it and modify.
delete from recurring_order;
alter table recurring_order drop column buyer_profile_id cascade;
alter table recurring_order drop column farmer_profile_id cascade;

alter table recurring_order add column schedule_id uuid not null references recurring_schedule(id) on delete cascade;
create index idx_recurring_order_schedule on recurring_order(schedule_id);

-- 3. Modify recurring_order_item
alter table recurring_order_item add column preferred_farmer_id uuid references farmer_profile(profile_id);

-- 4. Recreate policies based on schedule_id
create policy "recurring_order_select_own" on recurring_order for select using (
  exists (select 1 from recurring_schedule s where s.id = recurring_order.schedule_id and s.buyer_profile_id = auth.uid())
);
create policy "recurring_order_insert_own" on recurring_order for insert with check (
  exists (select 1 from recurring_schedule s where s.id = recurring_order.schedule_id and s.buyer_profile_id = auth.uid())
);
create policy "recurring_order_update_own" on recurring_order for update using (
  exists (select 1 from recurring_schedule s where s.id = recurring_order.schedule_id and s.buyer_profile_id = auth.uid())
);
create policy "recurring_order_delete_own" on recurring_order for delete using (
  exists (select 1 from recurring_schedule s where s.id = recurring_order.schedule_id and s.buyer_profile_id = auth.uid())
);

create policy "recurring_order_item_select_own" on recurring_order_item for select using (
  exists (
    select 1 from recurring_order ro 
    join recurring_schedule s on s.id = ro.schedule_id
    where ro.id = recurring_order_item.recurring_order_id and s.buyer_profile_id = auth.uid()
  )
);
create policy "recurring_order_item_insert_own" on recurring_order_item for insert with check (
  exists (
    select 1 from recurring_order ro 
    join recurring_schedule s on s.id = ro.schedule_id
    where ro.id = recurring_order_item.recurring_order_id and s.buyer_profile_id = auth.uid()
  )
);
create policy "recurring_order_item_delete_own" on recurring_order_item for delete using (
  exists (
    select 1 from recurring_order ro 
    join recurring_schedule s on s.id = ro.schedule_id
    where ro.id = recurring_order_item.recurring_order_id and s.buyer_profile_id = auth.uid()
  )
);

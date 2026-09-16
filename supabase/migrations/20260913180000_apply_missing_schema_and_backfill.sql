-- ============================================================
-- This migration applies all the DDL from 20260913105709 that was
-- never actually executed on the live DB (it was only marked
-- "applied" via `migration repair` without running), plus
-- 20260913105735's assign_nearest_driver rewrite (same issue).
-- It also backfills existing 'placed' orders that were stuck
-- because the columns/function were missing.
-- ============================================================

-- ============================================================
-- Section 1: Missing columns from 20260913105709
-- Add farmer_display_name and buyer_display_name to delivery
-- ============================================================
alter table delivery
  add column if not exists farmer_display_name text,
  add column if not exists buyer_display_name  text;

-- ============================================================
-- Section 2: Missing RLS policies from 20260913105709
-- ============================================================
do $$
begin
  if not exists (
    select 1 from pg_policies
    where tablename = 'orders' and policyname = 'orders_select_assigned_driver'
  ) then
    execute $policy$
      create policy "orders_select_assigned_driver" on orders for select using (
        exists (
          select 1 from delivery d
          join delivery_assignment da on da.delivery_id = d.id
          where d.order_id = orders.id
            and da.driver_profile_id = auth.uid()
            and da.is_current
        )
      )
    $policy$;
  end if;

  if not exists (
    select 1 from pg_policies
    where tablename = 'order_item' and policyname = 'order_item_select_assigned_driver'
  ) then
    execute $policy$
      create policy "order_item_select_assigned_driver" on order_item for select using (
        exists (
          select 1 from delivery d
          join delivery_assignment da on da.delivery_id = d.id
          where d.order_id = order_item.order_id
            and da.driver_profile_id = auth.uid()
            and da.is_current
        )
      )
    $policy$;
  end if;
end;
$$;

-- ============================================================
-- Section 3: Backfill — assign nearest driver to every order
-- that is still stuck at 'placed' with no delivery assigned.
-- ============================================================
do $$
declare
  v_order_id uuid;
begin
  for v_order_id in
    select id from orders
    where status = 'placed' and delivery_id is null
    order by placed_at asc
  loop
    begin
      perform assign_nearest_driver(v_order_id);
    exception when others then
      -- Log but don't abort the whole backfill if one order fails
      raise warning 'assign_nearest_driver failed for order %: %', v_order_id, sqlerrm;
    end;
  end loop;
end;
$$;

-- ============================================================
-- Fix: Infinite recursion in orders RLS policy + profile RLS policy
--
-- Root Cause:
-- 1. `profile_select_order_participants` policy on `profile` checks `orders`
-- 2. `orders_select_assigned_driver` policy on `orders` checks `delivery` / `delivery_assignment`
-- 3. `delivery_select_related` policy on `delivery` checks `orders`
-- 4. Circular evaluation: orders -> delivery -> orders -> infinite recursion (42P17)!
--
-- Solution:
-- Break the cyclic dependency in PostgreSQL RLS evaluation by:
-- 1. Using SECURITY DEFINER helper functions to check assignment access without triggering RLS loops.
-- 2. Simplifying policy expressions for orders, order_item, delivery and profile.
-- ============================================================

-- Helper function 1: Is user assigned as driver to a delivery? (Security definer avoids RLS loop)
create or replace function is_assigned_driver_for_order(p_order_id uuid, p_user_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1
    from delivery d
    join delivery_assignment da on da.delivery_id = d.id
    where d.order_id = p_order_id
      and da.driver_profile_id = p_user_id
      and da.is_current = true
  );
$$;

revoke execute on function is_assigned_driver_for_order(uuid, uuid) from public;
grant execute on function is_assigned_driver_for_order(uuid, uuid) to authenticated, service_role;


-- Helper function 2: Is user assigned as driver to a delivery ID?
create or replace function is_assigned_driver_for_delivery(p_delivery_id uuid, p_user_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1
    from delivery_assignment da
    where da.delivery_id = p_delivery_id
      and da.driver_profile_id = p_user_id
      and da.is_current = true
  );
$$;

revoke execute on function is_assigned_driver_for_delivery(uuid, uuid) from public;
grant execute on function is_assigned_driver_for_delivery(uuid, uuid) to authenticated, service_role;


-- 1. Fix orders RLS policy
drop policy if exists "orders_select_assigned_driver" on orders;

create policy "orders_select_assigned_driver" on orders for select using (
  is_assigned_driver_for_order(id, auth.uid())
);


-- 2. Fix order_item RLS policy
drop policy if exists "order_item_select_assigned_driver" on order_item;

create policy "order_item_select_assigned_driver" on order_item for select using (
  is_assigned_driver_for_order(order_id, auth.uid())
);


-- 3. Fix delivery RLS policy
drop policy if exists "delivery_select_related" on delivery;

create policy "delivery_select_related" on delivery for select using (
  exists (
    select 1 from orders o
    where o.id = delivery.order_id
      and (auth.uid() = o.buyer_profile_id or auth.uid() = o.farmer_profile_id)
  )
  or is_assigned_driver_for_delivery(id, auth.uid())
);


-- 4. Fix profile RLS policy to avoid orders recursion
drop policy if exists "profile_select_order_participants" on profile;

create policy "profile_select_order_participants" on profile for select using (
  exists (
    select 1 from orders o
    where (o.buyer_profile_id = auth.uid() or o.farmer_profile_id = auth.uid())
      and (profile.id = o.buyer_profile_id or profile.id = o.farmer_profile_id)
  )
  or exists (
    select 1 from delivery_assignment da
    where da.driver_profile_id = auth.uid()
      and da.is_current = true
  )
);

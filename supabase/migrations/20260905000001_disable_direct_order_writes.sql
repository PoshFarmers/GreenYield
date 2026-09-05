-- Enforce the plan decision: direct client inserts into orders, order_item,
-- and payment are disabled. The place_checkout SECURITY DEFINER function is
-- the only authorised write path for these tables.
--
-- The existing orders_insert_buyer policy was created in
-- 20260827093223_orders.sql. Because place_checkout runs as the DB owner
-- (SECURITY DEFINER) it already bypasses RLS, so removing the client insert
-- policy does not break checkout -- it only stops PowerSync's generic CRUD
-- uploader from ever pushing a locally-written orders row to Supabase.

drop policy if exists "orders_insert_buyer" on orders;

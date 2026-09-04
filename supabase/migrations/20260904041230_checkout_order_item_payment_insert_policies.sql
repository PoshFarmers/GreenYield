-- ============================================================
-- Checkout: buyer INSERT policies for order_item & payment
-- ------------------------------------------------------------
-- 20260827093223_orders.sql and 20260827094657_payment_and_refund.sql
-- only granted SELECT on order_item/payment (insert was assumed to
-- happen from trusted backend code once a payment gateway confirmed
-- the charge). Task 3.2's checkout flow writes these client-side via
-- PowerSync instead, so without an INSERT policy here RLS silently
-- rejects the upload — the row exists in the local PowerSync mirror
-- but never reaches Postgres, which is why local writes "work" (no
-- exception) while nothing shows up in the database.
--
-- Scope is kept tight: a buyer may only insert order_item/payment
-- rows attached to an `orders` row they themselves own, and a payment
-- may only be inserted as 'pending' — matching the only status
-- CheckoutService ever writes; every later transition (authorized,
-- captured, refunded, ...) still requires trusted backend code, same
-- as order status transitions in orders.sql.
-- ============================================================

create policy "order_item_insert_via_own_order" on order_item for insert with check (
  exists (
    select 1 from orders o
    where o.id = order_item.order_id
      and o.buyer_profile_id = auth.uid()
  )
);

create policy "payment_insert_own_pending" on payment for insert with check (
  auth.uid() = buyer_profile_id
  and status = 'pending'
  and exists (
    select 1 from orders o
    where o.id = payment.order_id
      and o.buyer_profile_id = auth.uid()
  )
);

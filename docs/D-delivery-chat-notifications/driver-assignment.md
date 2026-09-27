# Driver Assignment & Driver Home

**Owner:** Author D (Delivery, driver, chat, notifications)
**Reviewers:** Author C (checkout/orders), Author A (sync/RLS)
**Last verified against:** migrations up to `20260927093935_recurring_orders_rpc.sql`

## 1. Purpose

At checkout, every per-farmer order is auto-dispatched to the nearest driver. This doc covers the dispatch algorithm, what it writes, the driver's "today" screen data, and the driver's vehicle/route data. Status changes after assignment are in [delivery-tracking.md](delivery-tracking.md) and [../C-orders-payments/order-state-machine.md](../C-orders-payments/order-state-machine.md).

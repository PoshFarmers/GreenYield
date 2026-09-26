# Delivery Status, Tracking Schema & Driver Payout

**Owner:** Author D (Delivery, driver, chat, notifications)
**Reviewers:** Author C (order state machine, money), Author A (sync/RLS)
**Last verified against:** migrations up to `20260927093935_recurring_orders_rpc.sql`

> **Honesty note:** the delivery *status* flow, delivery RLS and the driver payout are implemented. Live GPS tracking, journeys, routes, route stops and ETA are **schema only**: no code in the dump writes `delivery_tracking`, `journey`, `route` or `route_stop`. The migrations say a trusted Edge Function would create journeys and routes, but no Edge Functions are in the dump.

## 1. Purpose

Describe how a delivery moves through its statuses, how that mirrors onto the order, who can read/write delivery data, how the driver is paid, and which tracking structures exist but are unused.

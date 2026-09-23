# Cross-Cutting Topics

**Owner:** Multiple (primary owner per topic below)
**Reviewers:** Multiple
**Last verified against:** migrations up to `20260927093935_recurring_orders_rpc.sql`

## 1. Purpose

Topics that span authors' areas. Each section gives a primary owner, secondary reviewers, the flow, files/migrations and pitfalls. Deep dives live in the per-area docs linked from each section.

## 2. End-to-end sequence

```mermaid
sequenceDiagram
    participant B as Buyer app
    participant CO as place_checkout
    participant AD as assign_nearest_driver
    participant W as Wallet
    participant F as Farmer app
    participant D as Driver app
    participant TD as transition_delivery_status
    B->>CO: request id, cart items, payment method, order date
    CO->>W: debit buyer when method is wallet
    CO->>CO: insert orders, order_item, payment, decrement stock
    CO->>AD: per order
    AD-->>CO: delivery and assignment, order assigned
    F->>F: mark_order_packed makes order packed
    D->>D: start_driver_shift notifies buyer and farmer
    D->>TD: picked_up then in_transit
    TD-->>TD: order picked_up then in_transit
    D->>TD: delivered
    TD->>W: payout of delivery fee to driver
    TD-->>TD: order delivered
    B->>B: submit_farmer_review
```

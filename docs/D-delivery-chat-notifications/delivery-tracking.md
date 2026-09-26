# Delivery Status, Tracking Schema & Driver Payout

**Owner:** Author D (Delivery, driver, chat, notifications)
**Reviewers:** Author C (order state machine, money), Author A (sync/RLS)
**Last verified against:** migrations up to `20260927093935_recurring_orders_rpc.sql`

> **Honesty note:** the delivery *status* flow, delivery RLS and the driver payout are implemented. Live GPS tracking, journeys, routes, route stops and ETA are **schema only**: no code in the dump writes `delivery_tracking`, `journey`, `route` or `route_stop`. The migrations say a trusted Edge Function would create journeys and routes, but no Edge Functions are in the dump.

## 1. Purpose

Describe how a delivery moves through its statuses, how that mirrors onto the order, who can read/write delivery data, how the driver is paid, and which tracking structures exist but are unused.

## 2. Key concepts

| Concept | Meaning |
|---|---|
| Delivery | One row per order (`delivery.order_id` unique). Created by dispatch, see [driver-assignment.md](driver-assignment.md). |
| Assignment | `delivery_assignment` row; the current one has `is_current = true`. History would be kept via `unassigned_at`. |
| Mirror | `transition_delivery_status` updates the delivery, then advances the order through `transition_order_status`. |
| Payout | On `delivered`, the driver's wallet is credited the order's `delivery_fee_amount`. |
| Display-name snapshot | `delivery.farmer_display_name` / `buyer_display_name`, see [../cross-cutting.md](../cross-cutting.md). |

## 3. Data model

| Table | Columns | Status |
|---|---|---|
| `delivery` | `id`, `order_id` UNIQUE (FK `orders`, restrict), `journey_id`, `pickup_location_text`, `pickup_location_point`, `dropoff_location_text`, `dropoff_location_point`, `status delivery_status`, `assigned_at`, `picked_up_at`, `delivered_at`, `farmer_display_name`, `buyer_display_name`, timestamps, mirrors `status_text`, `pickup_location_geojson`, `dropoff_location_geojson` | Used |
| `delivery_assignment` | `id`, `delivery_id`, `driver_profile_id`, `vehicle_id`, `assigned_at`, `unassigned_at`, `is_current` | Used (insert only) |
| `delivery_tracking` | `id`, `delivery_id`, `journey_id`, `location_point geography NOT NULL`, `speed_kmh`, `heading`, `recorded_at`, mirror `location_geojson` | No writer |
| `driver_schedule` | see [driver-assignment.md](driver-assignment.md) | Written by dispatch |
| `journey` | `driver_profile_id`, `vehicle_id`, `journey_date`, `direction` (`outbound`/`return`), `status journey_status` (`planned, in_progress, completed, cancelled`) | No writer |
| `route` | `journey_id` UNIQUE, `estimated_distance_km`, `estimated_duration_minutes` | No writer |
| `route_stop` | `route_id`, `delivery_id`, `stop_type` (`pickup`/`dropoff`), `sequence_number` (unique per route), `location_text`, `location_point`, `planned_arrival_at`, `actual_arrival_at` | No writer |

Enum `delivery_status`: `unassigned`, `assigned`, `picked_up`, `in_transit`, `delivered`. Dispatch inserts rows directly as `assigned`; `unassigned` is never set by any code in the dump.

## 4. Flow

```mermaid
stateDiagram-v2
    [*] --> assigned: assign_nearest_driver inserts
    assigned --> picked_up: driver calls transition_delivery_status
    picked_up --> in_transit
    in_transit --> delivered: payout of delivery fee
    delivered --> [*]
```

Delivery ↔ order status mapping (full order machine in [../C-orders-payments/order-state-machine.md](../C-orders-payments/order-state-machine.md)):

| Delivery status set | Order status requested | Note |
|---|---|---|
| `assigned` | `assigned` | Dispatch does not use this path (it inserts and transitions the order itself). |
| `picked_up` | `picked_up` | Allowed only if the order is `packed`. |
| `in_transit` | `in_transit` | from `picked_up` |
| `delivered` | `delivered` | from `in_transit` |
| `unassigned` | none | Delivery updated, order untouched. |

Order statuses with no delivery counterpart: `placed`, `confirmed`, `packed` (farmer action via `mark_order_packed`), `completed` (never set), `cancelled`.

## 5. RPCs and triggers

| Object | Definition | Behaviour |
|---|---|---|
| `transition_delivery_status(p_delivery_id uuid, p_new_status delivery_status) returns delivery` | Final `20260916050308_wallet_payment_and_payout`; SECURITY DEFINER; granted `authenticated, service_role` | 1) If `auth.uid()` is not null the caller must be the current assigned driver (`42501` otherwise). 2) Update delivery status and the matching timestamp (`assigned_at`, `picked_up_at`, `delivered_at`). 3) Raise if not found. 4) Map to an order status and call `transition_order_status(..., null, 'auto: delivery status sync')`. 5) If `delivered`, credit the current driver `delivery_fee_amount` via `apply_wallet_transaction(driver, 'payout', fee, 'delivery', delivery_id)` when the fee is greater than 0. |
| `estimate_delivery_eta(p_delivery_id uuid) returns timestamptz` | `20260827094054_delivery_tracking`; `stable`, SECURITY INVOKER | Last tracking ping + straight-line distance to `dropoff_location_point` at the average `speed_kmh` over the last 30 minutes (default 30 km/h). Null without pings or dropoff point. No caller in the dump. |
| `trg_notify_delivery_assignment` | AFTER INSERT on `delivery_assignment` | See [notification-events.md](notification-events.md). |
| Delivery-side notifications on status change | none | |

Everything runs in one transaction: if the order transition is invalid, the delivery update, timestamps and payout roll back together.

Payout details: paid only to the current assignment's driver, only when `delivery_fee_amount > 0`, type `payout`, reference `('delivery', delivery_id)`. Because the second `delivered` call fails on `delivered → delivered` in the order machine, the payout cannot be paid twice. The farmer and platform are not credited (see [../C-orders-payments/money-flow.md](../C-orders-payments/money-flow.md)).

## 6. RLS / permissions

| Table | Select | Write |
|---|---|---|
| `delivery` | `delivery_select_related` (final `20260915130000_fix_orders_rls_recursion`): buyer or farmer of the order (via `orders`), or `is_assigned_driver_for_delivery(id, auth.uid())` | none (server functions only) |
| `delivery_assignment` | `delivery_assignment_select_own` (`driver_profile_id = auth.uid()`) | none |
| `delivery_tracking` | buyer/farmer via delivery→orders, or current assigned driver | INSERT: current assigned driver (`delivery_tracking_insert_assigned_driver`) |
| `driver_schedule` | own | own insert/update/delete |
| `journey` | own | own update only (inserts "by trusted Edge Function") |
| `route`, `route_stop` | via own journey | `route_stop` update via own journey |

Helper functions `is_assigned_driver_for_order(uuid, uuid)` and `is_assigned_driver_for_delivery(uuid, uuid)` are SECURITY DEFINER SQL functions that break the RLS cycle `orders → delivery → orders`; the recursion fix and the policies that depend on them are in `20260915130000_fix_orders_rls_recursion`.

Buyers and farmers cannot read `delivery_assignment`; they get driver and vehicle data through the `get_order_detail` RPC ([../cross-cutting.md](../cross-cutting.md)).

## 7. Client data sources

| Screen / class | Source | Requirement |
|---|---|---|
| `OrderService.watchDeliveriesForDriver` | PostgREST embedded select `delivery_assignment → delivery → order → order_item → crop`, filtered `driver_profile_id = me` and `is_current = true`; filters by delivery status in Dart; **yields once** | RLS read on `delivery_assignment`, `delivery`, `orders`, `order_item`, `crop` |
| `OrderService.confirmPickup / markInTransit / markDelivered` | `transition_delivery_status` | |
| `OrderService.markOrderPacked` | `mark_order_packed` (farmer) | |
| `DriverHomeService` | see [driver-assignment.md](driver-assignment.md) | |
| Buyer/farmer order screens | local `orders`/`delivery` mirror + `get_order_detail` | |

Because the sync stream `own_deliveries_*` does not select `farmer_display_name`/`buyer_display_name`, the local `delivery` rows have those columns null; any local query that relies on them (e.g. `COALESCE(p_farmer.first_name ..., d.farmer_display_name)`) falls back to null offline.

## 8. Offline vs online

| Piece | Offline | Online |
|---|---|---|
| Local `delivery` status (buyer/farmer/driver) | Readable from the mirror (last synced) | Live via sync |
| Driver status changes | Fail (RPC only) | Work |
| Driver deliveries/calendar lists | Fail | Work |
| GPS tracking | not implemented | not implemented |

## 9. Edge cases and failure modes

- **No live tracking:** no code pings `delivery_tracking`; `estimate_delivery_eta` always returns null in practice.
- **Streams for absent tables:** sync-config has `own_journeys`, `own_routes`, `own_route_stops`, `own_delivery_tracking_*`, but these tables are not in `powersync_schema.dart`.
- **No reassignment or unassignment code:** `unassigned_at` is never set; if a driver drops out, nothing re-dispatches.
- **Delivery status is not validated on its own:** any status may be set by the assigned driver; only the order machine rejects invalid moves, and `unassigned` (or a repeat) is not order-guarded.
- **Cancellation:** `cancel_order` leaves the delivery and assignment untouched.
- **`delivery_fee_amount = 0`** (missing buyer/farmer location at checkout): no payout row is written.
- **Order deleted:** `delivery.order_id` is `ON DELETE RESTRICT`.

> ⚠ Unverified: `estimate_delivery_eta` has no explicit `grant`/`revoke`; confirm who can execute it on the live DB.
> ⚠ Unverified: Edge Functions that would create journeys/routes and insert tracking pings are not in the dump; confirm whether any exist in the Supabase project.

## 10. How to modify safely

1. To add live tracking: add the tables to `powersync_schema.dart` (or write pings via PostgREST), write pings only as the current assigned driver (policy already exists), and start/complete journeys from a single trusted place. Update the "schema only" banner here.
2. Change status mapping only inside `transition_delivery_status`, and re-check it against `transition_order_status` (a mismatch makes the whole RPC roll back).
3. If you add a delivery-status transition table, keep the order sync call last so an invalid order move aborts the delivery update.
4. Any change to payout must keep using `apply_wallet_transaction` and stay inside the same transaction; add farmer/platform legs in [../C-orders-payments/money-flow.md](../C-orders-payments/money-flow.md) terms.
5. When editing delivery/orders/profile RLS, test for `42P17` recursion and use the helper functions.

## Source files

`lib/features/orders/order_service.dart`, `lib/features/orders/order_providers.dart`, `lib/features/orders/order_detail_models.dart`, `lib/features/orders/driver_home_service.dart`, `lib/core/local_db/powersync_schema.dart`. Sync-config (path unconfirmed): `own_deliveries_buyer_or_farmer`, `own_deliveries_driver_assigned`, `own_delivery_assignments`, `own_delivery_tracking_*`, `own_journeys`, `own_routes`, `own_route_stops`. Migrations: `20260827093851_schedule_journey_route.sql`, `20260827094000_delivery_and_assignment.sql`, `20260827094054_delivery_tracking.sql`, `20260827094859_powersync_compat_view.sql`, `20260913105709_notify_and_driver_order_access.sql`, `20260915000000_mark_order_packed.sql`, `20260915130000_fix_orders_rls_recursion.sql`, `20260916050308_wallet_payment_and_payout.sql`, `20260827094613_wallet.sql`.
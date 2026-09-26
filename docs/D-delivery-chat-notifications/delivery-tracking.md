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

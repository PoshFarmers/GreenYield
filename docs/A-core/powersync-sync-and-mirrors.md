# PowerSync Sync Streams, Publication and Mirror Columns

**Owner:** Author A (Core)
**Reviewers:** Author B, Author C, Author D
**Last verified against:** migrations up to `20260927093935_recurring_orders_rpc.sql`, sync-config (path unconfirmed)

## 1. Purpose

Describes how Postgres data reaches the device: the Postgres publication, the PowerSync sync streams (edition 3), and the `*_text` / GeoJSON **mirror columns** that exist because PowerSync cannot replicate enums or geography reliably. See [data-access.md](data-access.md) for the upload direction.

## 2. Key concepts

- **Publication `powersync`**: Postgres logical-replication publication listing every table PowerSync may read.
- **Sync stream**: a named query in the PowerSync service config. It selects columns from **one source table**, filtered per user with `auth.user_id()`. All streams here are `auto_subscribe: true`.
- **Stream name != table name.** The local SQLite table takes the *source table* name (for example stream `marketplace_listings` fills local `produce_listing`; stream `market_prices` fills `market_price`).
- **Mirror column**: a plain `text` column maintained by a BEFORE trigger from an enum/geography column. Streams select the mirror and alias it back to the real name (`status_text as status`).

## 3. Why mirrors exist

`20260823070036_powersync_compat_view.sql` states the reasons: PowerSync replicates most reliably with plain scalar types, and `enum::text` (via `enum_out`) and `ST_AsGeoJSON` are `STABLE`, not `IMMUTABLE`, so they cannot be used in `GENERATED ... STORED` columns. A trigger is used instead.

Naming trap: the "powersync_compat_view" migrations create **no views**. They add columns and triggers.

| Migration | Scope |
|---|---|
| `20260823070036_powersync_compat_view` | `profile` only (first version) |
| `20260827094859_powersync_compat_view` | All other enum/geography tables (+ redefines the profile function) |
| `20260830035655_powersync_compat_publication_updates` | `profile_role.role_text`, `refund.refund_type_text`, publication rebuild |

Pattern (each table): `alter table ... add column if not exists x_text text;` then `drop trigger if exists` / `create trigger ... before insert or update of <enum cols> ...`, then a backfill `update t set col = col`. The backfill must reassign the watched column itself, because an `OF column_list` trigger fires only when those columns appear in the `SET` clause.

## 4. Mirror column inventory (final)

| Table | Source column(s) | Mirror column(s) | Trigger function |
|---|---|---|---|
| `profile` | `active_role`, `preferred_language`, `location_point` | `active_role_text`, `preferred_language_text`, `location_geojson` | `set_profile_powersync_mirrors` |
| `profile_role` | `role` | `role_text` | `set_profile_role_powersync_mirrors` |
| `crop` | `category` | `category_text` | `set_crop_powersync_mirrors` |
| `buyer_profile` | `buyer_type` | `buyer_type_text` | `set_buyer_profile_powersync_mirrors` |
| `vehicle` | `vehicle_type` | `vehicle_type_text` | `set_vehicle_powersync_mirrors` |
| `conversation` | `context_type` | `context_type_text` | `set_conversation_powersync_mirrors` |
| `notification_preference` | `channel` | `channel_text` | `set_notification_preference_powersync_mirrors` |
| `produce_listing` | `status` | `status_text` | `set_produce_listing_powersync_mirrors` |
| `orders` | `status`, `delivery_location` | `status_text`, `delivery_location_geojson` | `set_orders_powersync_mirrors` |
| `order_status_history` | `status` | `status_text` | `set_order_status_history_powersync_mirrors` |
| `recurring_order` | `frequency`, `status`, `delivery_location` | `frequency_text`, `status_text`, `delivery_location_geojson` | `set_recurring_order_powersync_mirrors` |
| `journey` | `status` | `status_text` | `set_journey_powersync_mirrors` |
| `route_stop` | `stop_type`, `location_point` | `stop_type_text`, `location_geojson` | `set_route_stop_powersync_mirrors` |
| `delivery` | `status`, `pickup_location_point`, `dropoff_location_point` | `status_text`, `pickup_location_geojson`, `dropoff_location_geojson` | `set_delivery_powersync_mirrors` |
| `delivery_tracking` | `location_point` | `location_geojson` | `set_delivery_tracking_powersync_mirrors` |
| `wallet_transaction` | `type` | `type_text` | `set_wallet_transaction_powersync_mirrors` |
| `payment` | `method`, `status` | `method_text`, `status_text` | `set_payment_powersync_mirrors` |
| `refund_request` | `status` | `status_text` | `set_refund_request_powersync_mirrors` |
| `refund` | `refund_type` | `refund_type_text` | `set_refund_powersync_mirrors` |

No mirror exists for `recurring_schedule.status` (enum `recurring_order_status`, added `20260927093817`); that table is also not in the publication. `farmer_review` has no enum columns.

How a client write round-trips: the local row holds `status_text` (for example `'active'`). On upload Postgres receives that column too, but for `produce_listing` the `status` enum takes
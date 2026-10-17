# Glossary

**Owner:** All authors (Author A maintains)
**Reviewers:** Author B, Author C, Author D
**Last verified against:** migrations up to `20260927093935_recurring_orders_rpc.sql`

## 1. Purpose

Definitions of project terms as used in these docs.

## 2. Terms

| Term | Definition |
|---|---|
| **Active role** | The role (`farmer`/`buyer`/`driver`) the user is currently acting as; stored in `profile.active_role` (local mirror `active_role_text`). If null the app falls back to the first role. See [A-core/auth-and-roles.md](A-core/auth-and-roles.md). |
| **Buyer profile / driver profile / farmer profile** | Role-specific 1:1 rows keyed by `profile_id`, each requiring a matching `profile_role` row. Farmer profile also holds `avg_rating`, `review_count`. |
| **Checkout group** | `orders.checkout_group_id`, shared by all per-farmer orders created in one checkout. |
| **Composite key** | A synthetic local id built from several columns (e.g. `farmer_crop`: `"<farmerProfileId>:<cropId>"`), described by `CompositeKey` in `TableConfig`. |
| **Crop** | Catalogue entry (`crop`): name, category (`vegetable`/`fruit`), fallback image. |
| **Delivery** | One row per order in `delivery`; carries pickup/dropoff points and the delivery status. |
| **Delivery assignment** | `delivery_assignment` row linking a delivery to a driver and vehicle; `is_current` marks the active one. |
| **Display id (GY-XXXXXX)** | Short id shown to users: `GY-` plus the first 6 hex characters of the uuid (dashes removed), uppercase. Used for orders, checkout groups and stops. |
| **Driver schedule** | `driver_schedule`: per driver per date availability and capacity override; upserted at dispatch. |
| **Farmer_crop (menu)** | The crops a farmer offers with their own description, default price and photo. Contrast with listings. |
| **Harvest (removed)** | Former table for harvest batches, dropped in `20260829153627_crop_produce_listing_rework`; `harvested_on` moved onto `produce_listing`. |
| **Journey / route / route stop** | Planned driver trip structures (`journey`, `route`, `route_stop`). Schema only, no writer. See [D-delivery-chat-notifications/delivery-tracking.md](D-delivery-chat-notifications/delivery-tracking.md). |
| **`last_read_at` cursor** | `conversation_participant.last_read_at`; messages from others newer than it are unread. |
| **LKR** | Sri Lankan rupee, the app's currency (`wallet.currency` default). |
| **Marketplace RPC** | SECURITY DEFINER search functions for buyers: `search_marketplace_listings`, `get_marketplace_listing`, `list_marketplace_farmers`. |
| **Market price / price trend / price history** | Analytics tables (`market_price`, `price_trend`, `price_history`) built from completed orders by `refresh_market_price_analytics`. |
| **Media queue** | Local sqflite database (`media_queue.db`) of pending uploads, independent of PowerSync. See [A-core/media-pipeline.md](A-core/media-pipeline.md). |
| **Mirror column** | Text/GeoJSON column maintained by a BEFORE trigger for an enum or geography column so PowerSync can replicate it (e.g. `status_text`, `location_geojson`). |
| **`new_message` notification** | Notification inserted for each chat message; hidden from the list by the client but still synced. |
| **`order_date`** | Buyer-chosen delivery date on `orders` (tomorrow or later); drives driver calendar and "today" stops. |
| **Payout** | Wallet transaction type `payout`; currently only the driver's delivery-fee credit on `delivered`. |
| **Powersync** | Service and client library that syncs a subset of Postgres into local SQLite and queues local writes. |
| **Pricing rule** | `pricing_rule` row defining the delivery fee: base + per-km rate, clamped to min/max; seeded 150 / 25 / 150 / 2000. |
| **Produce listing (inventory)** | A batch a farmer has for sale (`produce_listing`): price, available quantity, status (`active`, `sold_out`, `expired`, `flagged`). |
| **Profile** | Common `profile` row for every user (name, phone, address jsonb, location, language). Only the own row syncs. |
| **Publication** | Postgres logical replication set; `powersync` feeds PowerSync, `supabase_realtime` feeds Realtime. |
| **Realtime** | Supabase change streaming used by chat (`.stream()`), independent of PowerSync. |
| **Refund** | `refund` row created by `process_refund` (service role), crediting the buyer's wallet. Not triggered by any user flow. |
| **RLS** | Row Level Security: per-table policies deciding who may read/write rows through the API. |
| **Role** | `farmer`, `buyer` or `driver` (`user_role` enum, `profile_role` rows). One account may hold several. |
| **SE3050** | University module "User Experience Engineering" for which this project is built. |
| **SECURITY DEFINER** | Postgres function option that runs with the owner's privileges, used to read across RLS or perform trusted writes. |
| **Service role** | Supabase privileged role that bypasses RLS; `auth.uid()` is null. Used for backend-only functions. |
| **Stop** | A pickup or dropoff item on the driver's home screen (`DriverStop`). |
| **Sub-order** | Informal name for one `orders` row per farmer within a checkout. There is no `sub_orders` table. |
| **Sync stream** | A named PowerSync query (sync-config) defining which rows sync to a user. |
| **TableConfig / tableRegistry** | Dart registry (`table_registry.dart`) describing each synced table's real primary key, jsonb columns and composite key for uploads. |
| **Top-up** | Wallet credit through `topup_wallet(p_amount)` (amount above 0, at most 1,000,000). |
| **Vehicle capacity** | Dart name for `vehicle.max_load_kg` (a legacy column name repurposed as passenger capacity). |
| **Wallet / wallet transaction** | `wallet` (one per profile, balance never below 0) and `wallet_transaction` ledger rows. Types: `topup`, `payment`, `payout`, `refund`, `withdrawal`, `adjustment`; positive amount = credit. |
| **`checkout_request`** | Idempotency table for `place_checkout`, keyed by the client `request_id`. |

## Source files

`lib/models/*.dart`, `lib/core/local_db/*`, `lib/features/orders/order_detail_models.dart`, sync-config (path unconfirmed), migrations `20260815155858_generic_profile.sql`, `20260817223627_profile_role.sql`, `20260827093223_orders.sql`, `20260827094613_wallet.sql`, `20260829153627_crop_produce_listing_rework.sql`, `20260904170222_checkout_transaction.sql`, `20260915195819_seed_pricing_rule.sql`, `20260916050421_wallet_topup_rpc.sql`.
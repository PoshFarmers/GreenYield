# Cart

**Owner:** Author C (Cart, orders, wallet, payments)
**Reviewers:** Author B (listing stock/status), Author A (sync)
**Last verified against:** migrations up to `20260927093935_recurring_orders_rpc.sql`

## 1. Purpose

The buyer's cart is **local-first**: it lives in PowerSync tables and syncs to the server; only checkout is an RPC. One cart per buyer can hold items from several farmers and is split per farmer at checkout.

## 2. Data model

| Table | Columns / constraints |
|---|---|
| `cart` | `id`, `buyer_profile_id` (**unique**, FK `buyer_profile`), timestamps |
| `cart_item` | `id`, `cart_id`, `produce_listing_id` (FK cascade), `quantity_kg > 0`, timestamps; `unique(cart_id, produce_listing_id)` |

RLS: `cart` select/insert/update own (no delete); `cart_item` select/insert/update/delete via own cart. Sync: `own_cart`, `own_cart_items` (join through cart). Registry: both registered.

## 3. `CartService` (all local SQL)

| Method | Behaviour |
|---|---|
| `ensureCart(buyerId)` | Returns existing cart id or inserts one (`Uuid().v4()`) |
| `watchCartItems(buyerId)` | Joins `cart_item`, `cart`, local `produce_listing`, `crop`, `farmer_crop`; image `COALESCE(pl.image_url, fc.image_url, c.fallback_image_url)`; newest first |
| `watchItemCount(buyerId)` | `COUNT(cart_item.id)`: number of distinct items (not kg), returned as `double` |
| `addToCart` | Creates cart if needed; adds quantity or increases existing; clamps to current local `available_quantity_kg` |
| `updateQuantity` | Sets quantity; `<= 0` removes; clamps to stock |
| `removeItem`, `removeFarmerItems` | Deletes rows; farmer variant deletes all items of that farmer's listings |

Models: `CartLineItem` (price/stock are the **live** listing values; `isUnavailable = status != 'active' || stock <= 0`; `exceedsStock`; `lineTotal`) and `CartFarmerGroup` (per-farmer subtotal). Farmer display names are not available locally; callers enrich via `MarketplaceService.getListing`.

## 4. Checkout link

The buyer selects items, `CheckoutService.buildSummary` previews totals, and `place_checkout` validates each submitted `{id, quantity_kg}` against the **server** `cart_item` rows, then deletes those rows. The deletion syncs down and clears the local cart. See [checkout-rpc.md](checkout-rpc.md).

## 5. Offline vs online

Cart building and editing work fully offline. Checkout needs a connection and requires local edits to have uploaded first.

## 6. Edge cases

| Case | Detail |
|---|---|
| Edit then checkout before upload | RPC may raise `Cart item does not belong to buyer` or `Cart item quantity changed` |
| Listing leaves `active` | The stream `marketplace_listings` removes non-active rows from the local mirror; the `JOIN produce_listing` then drops those cart rows from the local view, so the UI's "unavailable" flags (`listingStatus != 'active'`) may never show for sold-out items |
| Listing deleted | `cart_item` cascades server-side; buyer gets `listing_removed_from_cart` |
| Zero stock on add | `_clamp` returns 0 when stock <= 0 or the listing is not in the local mirror, so a `quantity_kg = 0` row is inserted locally and would violate `quantity_kg > 0` on upload |
| Price changes | Cart shows current price; checkout charges the live price |
| Second device | Cart syncs, but sync lag can yield the checks above |
| Cart row race | A second `ensureCart` on another device could hit the unique `buyer_profile_id` on upload |

> ⚠ Unverified: (a) the local vanishing of non-active listings from cart joins; (b) the zero-quantity insert path; (c) upload failure handling if either occurs (see [../A-core/data-access.md](../A-core/data-access.md) §4).

## 7. How to modify safely

- Guard `addToCart` against `maxQty <= 0` (do not insert), and consider syncing the buyer's cart listings regardless of status.
- Keep quantity units as kg (`numeric` server, `REAL` local).
- Any new cart column needs the stream, `powersync_schema.dart`, and model updated together.
- Do not delete carts client-side (no policy).

## Source files

`lib/features/cart/cart_service.dart`; `lib/models/cart_item.dart`; `lib/features/orders/checkout_service.dart`; `lib/core/local_db/powersync_schema.dart`, `table_registry.dart`; sync-config YAML. Migrations: `20260827093107_cart`, `20260827094812_cross_component_foreign_keys`, `20260904170222_checkout_transaction`, `20260916050308_wallet_payment_and_payout`.
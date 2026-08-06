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


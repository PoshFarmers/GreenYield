# Checkout RPC (`place_checkout`)

**Owner:** Author C (Cart, orders, wallet, payments)
**Reviewers:** Author B (stock, fees), Author D (auto-assignment)
**Last verified against:** migrations up to `20260927093935_recurring_orders_rpc.sql`

## 1. Purpose

`place_checkout` is the single authorised write path that turns a cart into orders. It is atomic: stock lock, per-farmer orders, payments, wallet debit, driver assignment and cart cleanup succeed or fail together.

## 2. Signature

`place_checkout(p_request_id uuid, p_cart_items jsonb, p_payment_method text, p_delivery_address jsonb default null, p_order_date date default null) returns jsonb`
`security definer`, `search_path = public`, `revoke ... from public, anon; grant execute to authenticated`.
**Final definition:** `20260916050308_wallet_payment_and_payout.sql`.

| Parameter | Meaning |
|---|---|
| `p_request_id` | Idempotency key (client `Uuid().v4()` unless a `requestId` is passed) |
| `p_cart_items` | JSON array of `{id: cart_item uuid, quantity_kg}` |
| `p_payment_method` | `'wallet'` or `'card'` |
| `p_delivery_address` | jsonb (`line1`, `line2`, `city`, `postal_code`) or null |
| `p_order_date` | Requested delivery date; defaults to `now()::date + 1` |

Result: `{checkout_group_id, order_ids[], orders[{order_id, farmer_profile_id, items[{cart_item_id, produce_listing_id, crop_id, crop_name, quantity_kg, price_per_kg, line_total, image_url}], subtotal, delivery_fee, tax, total}], placed_at, order_date, delivery_address}`.

## 3. Sequence

```mermaid
sequenceDiagram
  participant App as CheckoutService
  participant RPC as place_checkout
  participant DB as Postgres
  App->>RPC: request_id, cart_items, method, address, order_date
  RPC->>DB: idempotency lookup in checkout_request
  alt already processed
    DB-->>App: stored result
  end
  RPC->>DB: lock buyer cart row
  RPC->>DB: validate each cart_item belongs to cart, quantity equals stored (lock rows)
  RPC->>DB: lock produce_listing rows: active, not expired, enough stock
  loop each farmer (ordered by id)
    RPC->>DB: build items and subtotal (image chain coalesce)
    RPC->>DB: fee = calculate_delivery_fee(farmer, buyer) or 0
    RPC->>DB: tax = round(subtotal*0.02, 2); total = subtotal + fee + tax
    RPC->>DB: insert orders (payment_id null), insert payment (pending), update orders.payment_id
    opt method = wallet
      RPC->>DB: apply_wallet_transaction(buyer, payment, -total, orders, order_id)
      RPC->>DB: payment.status = captured
    end
    RPC->>DB: insert order_item rows, decrement listing stock (sold_out at 0)
    RPC->>DB: assign_nearest_driver(order_id)
  end
  RPC->>DB: insert checkout_request (result), delete submitted cart_items
  RPC-->>App: result jsonb
```

## 4. Validation and errors

| Condition | Error / code |
|---|---|
| Not authenticated | `Authentication is required` `42501` |
| Empty or non-array items | `22023` |
| Payment method not wallet/card | `22023` |
| No cart row | `Cart not found` `P0001` |
| Bad item / quantity <= 0 | `Invalid cart item` `22023` |
| Item not in buyer's cart | `42501` |
| Quantity differs from server cart | `Cart item quantity changed` `P0001` |
| Listing missing, not `active`, expired, or short stock | `P0001` |
| Insufficient wallet balance | raised by `apply_wallet_transaction` (`P0001`), rolls back everything |

Client pre-checks (`CheckoutService.placeOrder`): non-empty cart; no item `isUnavailable` or `exceedsStock`; throws `StateError`. `p_order_date` is formatted `YYYY-MM-DD`.

## 5. Side effects

- Tables written: `orders`, `payment`, `order_item`, `produce_listing` (stock/status), `wallet`/`wallet_transaction` (wallet path), `delivery`, `delivery_assignment`, `driver_schedule`, `order_status_history`, `checkout_request`, `notification` (via triggers), and `cart_item` deletes.
- Order start status `placed`; on successful dispatch it becomes `assigned` within the same transaction.
- Triggers fired: `trg_notify_payment_status` (`payment_received` when wallet payment becomes `captured`), `trg_notify_delivery_assignment` (driver + buyer notifications). See [../D-delivery-chat-notifications/notification-events.md](../D-delivery-chat-notifications/notification-events.md).
- `assign_nearest_driver` returns silently if the farmer has no location or no eligible driver exists (order stays `placed`); any exception inside it aborts the whole checkout.

## 6. Money computation

`subtotal = sum(quantity * price_per_kg)` (live listing price, snapshotted into `order_item.price_per_kg`); `tax = round(subtotal * 0.02, 2)`; `fee` from [../B-marketplace/pricing-rules.md](../B-marketplace/pricing-rules.md); `total = subtotal + fee + tax`. `orders` stores `subtotal_amount`, `delivery_fee_amount`, `total_amount` only, so tax is derivable, not stored. `orders.delivery_location` and `delivery_location_geojson` are never populated.

## 7. Client behaviour (real vs commented)

`order_models.dart` and `CheckoutService` comments say orders are "written locally". That is stale: `placeOrder` calls the RPC, then builds `PlacedOrderGroup` from the response. `buildSummary` is a preview (per-farmer tax at `taxRate = 0.02`, fee estimate) and the RPC values are authoritative. Cart items are removed server-side; the deletion syncs down.

## 8. History (redefinitions)

| Migration | Change |
|---|---|
| `20260904170222_checkout_transaction` | Creates `checkout_request` and the 4-arg function; fee 0 |
| `20260905000001_disable_direct_order_writes` | Drops `orders_insert_buyer` |
| `20260905000002` | Insert payment before orders (violates circular FK) |
| `20260905000003` | Insert orders (null payment), then payment, then update |
| `20260905000004` | Image fallback chain in results |
| `20260913105735` | Adds `assign_nearest_driver` call (still 4-arg; inserts orders with `payment_id` before the payment exists) |
| `20260914000000_add_order_date` | New **5-arg** overload with `p_order_date` |
| `20260915092115` | Restores the dropped `assign_nearest_driver` call |
| `20260915190815` | Dynamic delivery fee |
| `20260916050308` | **Final:** wallet debit + capture |

> ⚠ Unverified: `20260914000000` created a 5-argument function with `create or replace`, which adds an overload rather than replacing the 4-arg one. No migration drops `place_checkout(uuid, jsonb, text, jsonb)`. If that legacy overload still exists, it remains executable by `authenticated` and bypasses the dynamic fee and wallet debit (fee 0, payment left `pending`). Dart always sends `p_order_date`, but confirm the overload was removed and drop it if not.

> ⚠ Unverified: `p_order_date` is not validated server-side (past dates are accepted; the "tomorrow or later" rule is client-only). Default uses `now()::date` in the DB timezone.

> ⚠ Unverified: idempotency depends on the client reusing `requestId`; `placeOrder` generates a new UUID per call if none is supplied, so a retry after a lost response can double-charge.

## 9. Offline vs online

Online only. Cart edits made offline must upload before checkout; the RPC validates against **server** `cart_item` rows.

## 10. Failure modes

Concurrent checkouts serialize on the cart and listing row locks. A stale price/stock or changed cart returns `P0001`; the UI should refresh the cart and retry. Card orders remain `pending` (see [money-flow.md](money-flow.md)).

## 11. How to modify safely

1. Copy the **latest** function body (`20260916050308`) when redefining; earlier redefinitions dropped features (`assign_nearest_driver`, then wallet). Add a comment listing what must be preserved.
2. Keep the same signature, or explicitly `drop function` the old one.
3. Re-run `revoke`/`grant` after every replace.
4. Keep server totals authoritative; update `CheckoutService.buildSummary` only as a preview.
5. If you add tax storage or payment gateways, extend `orders`/`payment` and the result JSON together.

## Source files

`lib/features/orders/checkout_service.dart`, `order_models.dart`; `lib/models/cart_item.dart`. Migrations: `20260904170222_checkout_transaction`, `20260905000001_disable_direct_order_writes`, `20260905000002_fix_checkout_insert_order`, `20260905000003_fix_checkout_circular_fk`, `20260905000004_fix_checkout_image_fallback`, `20260913105735_auto_assign_nearest_driver`, `20260914000000_add_order_date`, `20260915092115_fix_missing_driver_assignment_on_checkout`, `20260915190815_dynamic_delivery_fee_checkout`, `20260916050308_wallet_payment_and_payout`, `20260827094613_wallet`.
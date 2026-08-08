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


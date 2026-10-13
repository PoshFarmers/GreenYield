# Pricing Rules

**Owner:** Author B (Marketplace)
**Reviewers:** Author C (checkout totals), Author D (driver payout = delivery fee)
**Last verified against:** migrations up to `20260927093935_recurring_orders_rpc.sql`

## 1. Purpose

Three separate pricing mechanisms exist and should not be confused: the **delivery fee formula** (server-authoritative), the **client preview** of it, and **crop price bounds** (client-side hints). Market analytics is separate, see [market-analytics.md](market-analytics.md).

## 2. Delivery fee

### Data model: `pricing_rule`

`id`, `name`, `base_fee`, `per_km_rate`, `min_fee`, `max_fee`, `effective_from`, `effective_to`, `is_active`, `created_at`. RLS: select all; no client write policies. Seed row (`20260915195819_seed_pricing_rule`, only if no active rule exists): **"Standard delivery": base 150, per km 25, min 150, max 2000 (LKR)**, effective from `now() - 1 day`.

### Formula

```
fee = base_fee + distance_km * per_km_rate
fee = max(fee, min_fee) if min_fee not null
fee = min(fee, max_fee) if max_fee not null
fee = round(fee, 2)
```

With the seed rule: 0 km -> 150; 10 km -> 400; 80 km -> 2000 (cap).

### Server: `calculate_delivery_fee(geography, geography)`

Final definition `20260827094740_pricing_and_market_intelligence.sql`; `stable`, invoker, granted to `authenticated`.
1. Picks the active rule: `is_active`, `effective_from <= now()`, `effective_to is null or > now()`, newest `effective_from`, `limit 1`.
2. No rule -> returns `0`.
3. `km = ST_Distance(pickup, dropoff) / 1000` (straight-line geography, not road distance).

Used only by `place_checkout` (per farmer order), only when both farmer and buyer `profile.location_point` are non-null; otherwise the fee is `0` (`20260915190815`, kept by `20260916050308`). The fee lands in `orders.delivery_fee_amount` and is later paid to the driver (see [../C-orders-payments/money-flow.md](../C-orders-payments/money-flow.md)).

### Client preview: `DeliveryFeeService`

Reads the active rule from the local `pricing_rule` mirror (stream `pricing_rules`, `is_active = 1`, ISO-string date comparison) and applies the same formula (`applyRule`, `toStringAsFixed(2)`). `estimateFee(distanceKm)` returns `null` if distance or rule is missing. Distance comes from `MarketplaceListing.distanceKm` (RPC, buyer coordinates passed by the client).

| Aspect | Client (`CheckoutService.buildSummary`) | Server (`place_checkout`) |
|---|---|---|
| Rule source | local mirror | `pricing_rule` table |
| Distance | marketplace `distance_km` (buyer point supplied by client) | `profile.location_point` of buyer and farmer |
| Missing data | fee null -> treated as 0 | fee 0 |
| Tax | `subtotal * 0.02` (`CheckoutService.taxRate`), **unrounded** | `round(subtotal * 0.02, 2)` |
| Authority | preview only | authoritative; response replaces preview |

Numbers can differ by fractions of a cent (tax rounding), or more if a location changed between preview and confirm. Fee is **per farmer order**, not per checkout.

> ⚠ Unverified: tax rate 2% is hard-coded in both `CheckoutService.taxRate` and SQL (`0.02`); nothing links them. `orders` has no tax column, so tax is only implicit in `total_amount`.

## 3. Crop price bounds (`crop_price_bounds.dart`)

A hard-coded map of crop name -> `(min, max)` LKR/kg, with default `(100, 300)` for unknown names (`priceBoundsFor`). It is **client-only, not enforced in the database** (the migration comment says "Bounds enforced client-side in Flutter for now"). It guides farmers' listing prices; the server accepts any `price_per_kg >= 0`.

Relationship to analytics: `market_price` (server, computed from completed orders) is real observed data synced to the app; `crop_price_bounds` is a static guardrail. They are independent and can disagree.

> ⚠ Unverified: keys include `Brinjal` and `Capsicum`, but the seeded crop names are `Eggplant` and `Red bell pepper` (`20260818012120_farmer_profile`), so those crops fall back to the default bounds. Names created by `scripts/upload_crop_fallback_images.dart` come from image filenames and may differ again.

## 4. Offline vs online

Fee preview works offline once `pricing_rules` has synced (distance must already be known). Actual checkout requires a connection.

## 5. Edge cases

- Overlapping active rules: newest `effective_from` wins.
- No active rule: fee 0 on the server, null (0) on the client.
- Minimum fee applies at zero distance.
- Straight-line distance underestimates road distance.
- Fee is calculated using profile locations, not the order's `delivery_address`.

## 6. How to change safely

- Change fees by inserting a new `pricing_rule` row (new `effective_from`) and deactivating or ending the old one; no deploy needed. Synced clients pick it up on next sync.
- If you change the formula, change SQL and `DeliveryFeeService.applyRule` together.
- Move the tax rate into a table or shared constant before changing it.
- To enforce price bounds, add a server-side check or trigger; currently none exists.

## Source files

`lib/features/pricing/delivery_fee_service.dart`; `lib/models/pricing_rule.dart`; `lib/features/orders/checkout_service.dart`; `lib/features/profile/farmer/crop_price_bounds.dart`; `lib/models/marketplace_listing.dart`; sync-config YAML (`pricing_rules`). Migrations: `20260827094740_pricing_and_market_intelligence`, `20260915190815_dynamic_delivery_fee_checkout`, `20260915195819_seed_pricing_rule`, `20260916050308_wallet_payment_and_payout`, `20260818012120_farmer_profile`, `20260829153627_crop_produce_listing_rework`.
# GreenYield Developer Documentation

**Owner:** All authors (Author A maintains)
**Reviewers:** Author B, Author C, Author D
**Last verified against:** migrations up to `20260927093935_recurring_orders_rpc.sql`

Developer-facing documentation for GreenYield, a Flutter marketplace connecting farmers, buyers and delivery drivers in Sri Lanka (LKR; en/si/ta). University project for SE3050 User Experience Engineering, built by four developers. The docs cover functionality, logic and logistics (data flow, state machines, money, business rules, backend behaviour), not UI layout.

**Source of truth:** the SQL migrations in `supabase/migrations/` decide server behaviour; later files override earlier ones, and each doc cites the migration that last redefined an object. Anything unclear is marked `> ⚠ Unverified:` and collected in [VERIFY.md](VERIFY.md).

## 1. Ownership

| Owner | Area | Docs folder |
|---|---|---|
| Author A | Core: auth, profiles, PowerSync, media, theming, i18n | `A-core/` |
| Author B | Marketplace, listings, pricing, market analytics | `B-marketplace/` |
| Author C | Cart, checkout, orders, wallet, payments, reviews, recurring orders | `C-orders-payments/` |
| Author D | Delivery, driver, chat, notifications | `D-delivery-chat-notifications/` |

## 2. Index

| Doc | Topic |
|---|---|
| [glossary.md](glossary.md) | Project terms |
| [cross-cutting.md](cross-cutting.md) | Multi-owner topics and the end-to-end sequence |
| [se3050-mapping.md](se3050-mapping.md) | Mapping to Lab 09 / 10 / 11 |
| [VERIFY.md](VERIFY.md) | Open questions and flagged issues, by owner |
| [A-core/architecture-overview.md](A-core/architecture-overview.md) | Two data paths, layers |
| [A-core/data-access.md](A-core/data-access.md) | Repository, connector, RPC access |
| [A-core/powersync-sync-and-mirrors.md](A-core/powersync-sync-and-mirrors.md) | Streams, publications, mirror columns |
| [A-core/add-a-synced-table.md](A-core/add-a-synced-table.md) | Checklist for a new synced table |
| [A-core/auth-and-roles.md](A-core/auth-and-roles.md) | Sign-in, profile, roles, routing |
| [A-core/media-pipeline.md](A-core/media-pipeline.md) | Upload queue, cache, buckets |
| [A-core/theming-and-i18n.md](A-core/theming-and-i18n.md) | Theme and translations |
| [B-marketplace/listing-lifecycle.md](B-marketplace/listing-lifecycle.md) | Crops, listings, statuses |
| [B-marketplace/pricing-rules.md](B-marketplace/pricing-rules.md) | Delivery fee, tax, price bounds |
| [B-marketplace/search-rpcs.md](B-marketplace/search-rpcs.md) | Search and discovery RPCs |
| [B-marketplace/market-analytics.md](B-marketplace/market-analytics.md) | Price history, trends |
| [C-orders-payments/order-state-machine.md](C-orders-payments/order-state-machine.md) | Order statuses and transitions |
| [C-orders-payments/checkout-rpc.md](C-orders-payments/checkout-rpc.md) | `place_checkout` |
| [C-orders-payments/money-flow.md](C-orders-payments/money-flow.md) | Wallet, payments, refunds, payout |
| [C-orders-payments/cart.md](C-orders-payments/cart.md) | Local-first cart |
| [C-orders-payments/reviews.md](C-orders-payments/reviews.md) | Farmer ratings |
| [C-orders-payments/recurring-orders.md](C-orders-payments/recurring-orders.md) | Recurring orders (incomplete) |
| [D-delivery-chat-notifications/driver-assignment.md](D-delivery-chat-notifications/driver-assignment.md) | Dispatch and driver home |
| [D-delivery-chat-notifications/delivery-tracking.md](D-delivery-chat-notifications/delivery-tracking.md) | Delivery status, payout, tracking schema |
| [D-delivery-chat-notifications/chat-realtime.md](D-delivery-chat-notifications/chat-realtime.md) | Chat over Realtime |
| [D-delivery-chat-notifications/notification-events.md](D-delivery-chat-notifications/notification-events.md) | Notification events and client |

## 3. Recommended reading order

1. [A-core/architecture-overview.md](A-core/architecture-overview.md), then [A-core/data-access.md](A-core/data-access.md) and [A-core/powersync-sync-and-mirrors.md](A-core/powersync-sync-and-mirrors.md): why data takes two paths.
2. [A-core/auth-and-roles.md](A-core/auth-and-roles.md): how a user reaches a role-specific shell.
3. [B-marketplace/listing-lifecycle.md](B-marketplace/listing-lifecycle.md), [B-marketplace/search-rpcs.md](B-marketplace/search-rpcs.md), [C-orders-payments/cart.md](C-orders-payments/cart.md): browsing to cart.
4. [C-orders-payments/checkout-rpc.md](C-orders-payments/checkout-rpc.md), [C-orders-payments/order-state-machine.md](C-orders-payments/order-state-machine.md), [C-orders-payments/money-flow.md](C-orders-payments/money-flow.md): the core transaction.
5. [D-delivery-chat-notifications/driver-assignment.md](D-delivery-chat-notifications/driver-assignment.md) and [D-delivery-chat-notifications/delivery-tracking.md](D-delivery-chat-notifications/delivery-tracking.md): fulfilment.
6. [C-orders-payments/reviews.md](C-orders-payments/reviews.md), [D-delivery-chat-notifications/chat-realtime.md](D-delivery-chat-notifications/chat-realtime.md), [D-delivery-chat-notifications/notification-events.md](D-delivery-chat-notifications/notification-events.md).
7. [cross-cutting.md](cross-cutting.md), then [VERIFY.md](VERIFY.md) before changing anything risky.
8. [glossary.md](glossary.md) whenever a term is unfamiliar; [se3050-mapping.md](se3050-mapping.md) when preparing lab material.

## 4. Status warnings

- Recurring orders are schema plus a broken draft RPC, not a feature.
- Live GPS tracking, ETA, journeys and routes are schema only.
- No farmer or platform settlement exists; only the driver's delivery-fee payout does.
- Market analytics need `completed` orders and nothing sets `completed`.
- Push, SMS and email notifications do not exist (in-app rows only).

## 5. How to contribute to the docs

1. **Header:** every doc starts with the title, then `**Owner:**`, `**Reviewers:**`, `**Last verified against:**` (latest migration you checked).
2. **Structure:** numbered sections: Purpose, Key concepts, data model, flow (Mermaid), RPCs/triggers, RLS/permissions, offline vs online, edge cases, how to modify safely, then `## Source files`.
3. **Accuracy:** document only the final effective definition of each function, policy or trigger and cite the migration file that last redefined it, using the actual filename (see the mismatch table in [cross-cutting.md](cross-cutting.md)). Never describe behaviour you did not verify in the code or SQL.
4. **Unknowns:** write `> ⚠ Unverified: <what to confirm>` inline and add a checkbox entry to [VERIFY.md](VERIFY.md) under the right owner with the next free id.
5. **Tone:** precise and developer-facing; prefer tables for enums, statuses, RPC signatures and permissions.
6. **Diagrams:** use Mermaid, and render it before committing (avoid `;` and unbalanced quotes in labels).
7. **Links:** relative, matching the folder layout (`../A-core/data-access.md` from a subfolder).
8. **Same PR rule:** any migration or provider change that alters documented behaviour updates its doc, [cross-cutting.md](cross-cutting.md) if it spans owners, and [VERIFY.md](VERIFY.md) in the same PR.
9. **Self-check before merging:** owner header present, `Source files` present, Mermaid valid, links resolve (`grep -rn "](" docs/` and open them), no claim beyond the code; run `grep -rn "⚠ Unverified" docs/` and confirm every hit is in VERIFY.md.

## Source files

Repository layout as delivered in the dump: `pubspec.yaml`, `supabase/config.toml`, `supabase/migrations/*`, `lib/**`, `scripts/upload_crop_fallback_images.dart`, and the PowerSync sync-config (path unconfirmed). The repository root `README.md` is still the default Flutter template and does not describe the project.
import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../core/local_db/powersync.dart'; // exposes `db`
import '../../models/cart_item.dart';
import '../../models/profile.dart';
import 'order_models.dart';

/// Sprint 2 — Task 3.2: Order Creation & Checkout Flow.
///
/// Mirrors [CartService]'s local-first shape: everything here writes
/// straight to the on-device PowerSync mirror (`orders`, `order_item`,
/// `payment`) inside a single transaction, then relies on PowerSync's
/// CRUD queue to push it out to Supabase once connectivity returns —
/// a buyer can place an order entirely offline.
///
/// There is no `sub_orders` table server-side (see
/// `supabase/migrations/20260827093223_orders.sql`): a multi-farmer
/// checkout is represented as one `orders` row *per farmer*, all
/// sharing the same `checkout_group_id`. That shared id is what lets
/// the UI treat "one checkout" as a single unit even though each
/// farmer's slice is its own order/payment row under the hood, e.g.
/// for independent status tracking per farmer later.
///
/// `delivery_fee_amount` and tax are hardcoded for now (Sprint 2 scope
/// doesn't include live delivery pricing yet — that's `pricing_rule`,
/// wired up in a later sprint). Because `orders` has no separate tax
/// column, tax is folded into `total_amount` and simply broken out as
/// its own line in the UI for transparency.
class CheckoutService {
  static const _uuid = Uuid();

  /// Flat delivery fee charged per farmer sub-order (LKR), until
  /// `pricing_rule` is wired up for real distance-based delivery
  /// pricing.
  static const double flatDeliveryFeePerSubOrder = 350;

  /// Flat tax rate applied to each farmer's subtotal, until proper
  /// tax handling lands.
  static const double taxRate = 0.02;

  const CheckoutService();

  /// Splits [items] into one [CheckoutSubOrder] per farmer and computes
  /// the same subtotal/fee/tax/total breakdown [placeOrder] will
  /// actually charge — so the checkout screen can render an accurate
  /// price breakdown before the buyer taps "Place Order".
  CheckoutSummary buildSummary(List<CartLineItem> items) {
    final byFarmer = <String, List<CartLineItem>>{};
    for (final item in items) {
      byFarmer.putIfAbsent(item.farmerProfileId, () => []).add(item);
    }

    final subOrders = byFarmer.entries.map((entry) {
      final subtotal = entry.value.fold<double>(
        0,
        (sum, item) => sum + item.lineTotal,
      );
      final tax = subtotal * taxRate;
      return CheckoutSubOrder(
        farmerProfileId: entry.key,
        items: entry.value,
        subtotal: subtotal,
        deliveryFee: flatDeliveryFeePerSubOrder,
        tax: tax,
      );
    }).toList();

    return CheckoutSummary(subOrders: subOrders);
  }

  /// Creates one `orders` row (+ `order_item` rows + a `payment` row)
  /// per farmer represented in [items], all sharing a fresh
  /// `checkout_group_id`, then clears those items out of the buyer's
  /// cart. Returns the [PlacedOrderGroup] the confirmation screen needs.
  ///
  /// Every write happens in a single `db.writeTransaction` so a crash
  /// mid-checkout can never leave a partial set of sub-orders behind.
  Future<PlacedOrderGroup> placeOrder({
    required Profile buyerProfile,
    required List<CartLineItem> items,
    required String paymentMethod, // 'wallet' | 'card'
  }) async {
    if (items.isEmpty) {
      throw StateError('Cannot check out an empty cart');
    }
    if (items.any((item) => item.isUnavailable || item.exceedsStock)) {
      throw StateError('Cart has unavailable items');
    }

    final summary = buildSummary(items);
    final checkoutGroupId = _uuid.v4();
    final now = DateTime.now().toIso8601String();
    final deliveryAddressJson = buyerProfile.address.isEmpty
        ? null
        : jsonEncode(buyerProfile.address.toMap());

    final placedOrderIds = <String>[];

    await db.writeTransaction((tx) async {
      for (final subOrder in summary.subOrders) {
        final orderId = _uuid.v4();
        final paymentId = _uuid.v4();

        await tx.execute(
          '''
          INSERT INTO orders (
            id, checkout_group_id, buyer_profile_id, farmer_profile_id,
            status, payment_id, subtotal_amount, delivery_fee_amount,
            total_amount, delivery_address, placed_at, created_at, updated_at
          ) VALUES (?, ?, ?, ?, 'placed', ?, ?, ?, ?, ?, ?, ?, ?)
          ''',
          [
            orderId,
            checkoutGroupId,
            buyerProfile.id,
            subOrder.farmerProfileId,
            paymentId,
            subOrder.subtotal,
            subOrder.deliveryFee,
            subOrder.total,
            deliveryAddressJson,
            now,
            now,
            now,
          ],
        );

        for (final item in subOrder.items) {
          await tx.execute(
            '''
            INSERT INTO order_item (
              id, order_id, produce_listing_id, crop_id, quantity_kg,
              price_per_kg, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            ''',
            [
              _uuid.v4(),
              orderId,
              item.produceListingId,
              item.cropId,
              item.quantityKg,
              item.pricePerKg,
              now,
            ],
          );
        }

        // Payment starts 'pending' — actual authorization/capture is a
        // trusted backend concern (see payment_and_refund.sql), not
        // something a client can set directly. The wallet/card choice
        // is UI-only at this stage per Sprint 2 scope.
        await tx.execute(
          '''
          INSERT INTO payment (
            id, order_id, buyer_profile_id, method, amount, status, created_at, updated_at
          ) VALUES (?, ?, ?, ?, ?, 'pending', ?, ?)
          ''',
          [
            paymentId,
            orderId,
            buyerProfile.id,
            paymentMethod,
            subOrder.total,
            now,
            now,
          ],
        );

        await tx.execute(
          '''
          DELETE FROM cart_item
          WHERE produce_listing_id IN (
            SELECT id FROM produce_listing WHERE farmer_profile_id = ?
          )
          AND cart_id = (SELECT id FROM cart WHERE buyer_profile_id = ?)
          ''',
          [subOrder.farmerProfileId, buyerProfile.id],
        );

        placedOrderIds.add(orderId);
      }
    });

    return PlacedOrderGroup(
      checkoutGroupId: checkoutGroupId,
      orderIds: placedOrderIds,
      summary: summary,
      placedAt: DateTime.now(),
      deliveryAddress: buyerProfile.address,
    );
  }
}

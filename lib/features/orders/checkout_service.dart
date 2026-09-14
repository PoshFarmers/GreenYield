import 'dart:developer' as developer;

import 'package:uuid/uuid.dart';

import '../../core/supabase/client.dart';
import '../../models/cart_item.dart';
import '../../models/profile.dart';
import 'order_models.dart';

/// Sprint 2 — Task 3.2: Order Creation & Checkout Flow.
///
/// Cart reads remain local-first, but order creation is performed by the
/// authenticated Supabase `place_checkout` RPC so validation, stock changes,
/// order rows, and payment rows share one server transaction.
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
  static const double flatDeliveryFeePerSubOrder = 0;

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

  /// Creates one order per farmer through the server-side checkout
  /// transaction. The RPC also clears the submitted cart items.
  Future<PlacedOrderGroup> placeOrder({
    required Profile buyerProfile,
    required List<CartLineItem> items,
    required String paymentMethod, // 'wallet' | 'card'
    required DateTime orderDate,
    String? requestId,
  }) async {
    if (items.isEmpty) {
      throw StateError('Cannot check out an empty cart');
    }
    if (items.any((item) => item.isUnavailable || item.exceedsStock)) {
      throw StateError('Cart has unavailable items');
    }

    developer.log(
      'Calling place_checkout RPC — items: ${items.length}, method: $paymentMethod',
      name: 'GreenYield.CheckoutService',
    );

    final response = await supabase.rpc(
      'place_checkout',
      params: {
        'p_request_id': requestId ?? _uuid.v4(),
        'p_cart_items': items
            .map(
              (item) => {'id': item.cartItemId, 'quantity_kg': item.quantityKg},
            )
            .toList(),
        'p_payment_method': paymentMethod,
        'p_delivery_address': buyerProfile.address.isEmpty
            ? null
            : buyerProfile.address.toMap(),
        'p_order_date':
            '${orderDate.year.toString().padLeft(4, '0')}-'
            '${orderDate.month.toString().padLeft(2, '0')}-'
            '${orderDate.day.toString().padLeft(2, '0')}',
      },
    );

    developer.log(
      'place_checkout RPC response type: ${response.runtimeType}',
      name: 'GreenYield.CheckoutService',
    );

    if (response == null) {
      throw StateError('place_checkout returned null response');
    }

    final result = Map<String, dynamic>.from(response as Map);
    final orderData = (result['orders'] as List)
        .map((order) => Map<String, dynamic>.from(order as Map))
        .toList();

    // Parse the order_date returned by the RPC (format: 'YYYY-MM-DD').
    final rawOrderDate = result['order_date'];
    final parsedOrderDate = rawOrderDate is String
        ? DateTime.tryParse(rawOrderDate) ?? orderDate
        : orderDate;

    return PlacedOrderGroup(
      checkoutGroupId: result['checkout_group_id'] as String,
      orderIds: orderData.map((order) => order['order_id'] as String).toList(),
      summary: CheckoutSummary(
        subOrders: orderData.map(_subOrderFromResponse).toList(),
      ),
      placedAt: DateTime.parse(result['placed_at'] as String),
      deliveryAddress: buyerProfile.address,
      orderDate: parsedOrderDate,
    );
  }

  CheckoutSubOrder _subOrderFromResponse(Map<String, dynamic> order) {
    final items = (order['items'] as List).map((rawItem) {
      final item = Map<String, dynamic>.from(rawItem as Map);
      return CartLineItem(
        cartItemId: item['cart_item_id'] as String,
        produceListingId: item['produce_listing_id'] as String,
        farmerProfileId: order['farmer_profile_id'] as String,
        cropId: item['crop_id'] as String,
        cropName: item['crop_name'] as String,
        category: 'vegetable',
        pricePerKg: _toDouble(item['price_per_kg']),
        availableQuantityKg: _toDouble(item['quantity_kg']),
        listingStatus: 'active',
        quantityKg: _toDouble(item['quantity_kg']),
        imageUrl: item['image_url'] as String?,
      );
    }).toList();

    return CheckoutSubOrder(
      farmerProfileId: order['farmer_profile_id'] as String,
      items: items,
      subtotal: _toDouble(order['subtotal']),
      deliveryFee: _toDouble(order['delivery_fee']),
      tax: _toDouble(order['tax']),
    );
  }

  /// Supabase RPC returns PostgreSQL `numeric` columns as JSON strings
  /// (e.g. "5.00") rather than JSON numbers to preserve decimal precision.
  /// This helper handles both forms so the caller doesn't crash.
  double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) return double.parse(value);
    throw ArgumentError(
      'Cannot convert $value (${value.runtimeType}) to double',
    );
  }
}

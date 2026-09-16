import 'dart:developer' as developer;

import 'package:uuid/uuid.dart';

import '../../core/supabase/client.dart';
import '../../models/cart_item.dart';
import '../../models/profile.dart';
import '../pricing/delivery_fee_service.dart';
import 'order_models.dart';

/// Order Creation & Checkout Flow.
class CheckoutService {
  static const _uuid = Uuid();

  /// Flat tax rate applied to each farmer's subtotal.
  static const double taxRate = 0.02;

  const CheckoutService();

  /// Splits [items] into one [CheckoutSubOrder] per farmer and
  /// estimates the same delivery-fee formula place_checkout will
  /// actually charge — via [DeliveryFeeService], using [farmerDistanceKm]
  /// (farmerProfileId -> distance from the buyer) supplied by the
  /// caller from whatever marketplace enrichment it already has on
  /// hand. Falls back to an unknown/0 fee per farmer when no distance
  /// is available yet, same as PriceBreakdownCard's fallback.
  Future<CheckoutSummary> buildSummary(
    List<CartLineItem> items, {
    Map<String, double?> farmerDistanceKm = const {},
  }) async {
    final byFarmer = <String, List<CartLineItem>>{};
    for (final item in items) {
      byFarmer.putIfAbsent(item.farmerProfileId, () => []).add(item);
    }

    final deliveryFeeService = const DeliveryFeeService();
    final subOrders = <CheckoutSubOrder>[];

    for (final entry in byFarmer.entries) {
      final subtotal = entry.value.fold<double>(
        0,
        (sum, item) => sum + item.lineTotal,
      );
      final tax = subtotal * taxRate;
      final fee =
          await deliveryFeeService.estimateFee(farmerDistanceKm[entry.key]) ??
          0;
      subOrders.add(
        CheckoutSubOrder(
          farmerProfileId: entry.key,
          items: entry.value,
          subtotal: subtotal,
          deliveryFee: fee,
          tax: tax,
        ),
      );
    }

    return CheckoutSummary(subOrders: subOrders);
  }

  /// Creates one order per farmer through the server-side checkout
  /// transaction. The RPC computes the real delivery fee itself
  /// (calculate_delivery_fee) — this client-side [buildSummary] is
  /// only a preview and may differ slightly if a location changed
  /// between preview and confirm; the RPC's number is authoritative.
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

    if (response == null) {
      throw StateError('place_checkout returned null response');
    }

    final result = Map<String, dynamic>.from(response as Map);
    final orderData = (result['orders'] as List)
        .map((order) => Map<String, dynamic>.from(order as Map))
        .toList();

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

  double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) return double.parse(value);
    throw ArgumentError(
      'Cannot convert $value (${value.runtimeType}) to double',
    );
  }
}

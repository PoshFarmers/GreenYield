import 'dart:developer' as developer;

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/local_db/powersync.dart';
import '../../core/supabase/client.dart';
import '../../models/cart_item.dart';
import '../../models/profile.dart';
import '../payments/payment_gateway.dart';
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
    String? linkedCardId,
  }) async {
    if (items.isEmpty) {
      throw StateError('Cannot check out an empty cart');
    }
    if (items.any((item) => item.isUnavailable || item.exceedsStock)) {
      throw StateError('Cart has unavailable items');
    }

    await _ensureServerCart(
      buyerProfileId: buyerProfile.id,
      cartItemIds: items.map((item) => item.cartItemId).toSet(),
    );

    developer.log(
      'Calling place_checkout RPC — items: ${items.length}, method: $paymentMethod',
      name: 'GreenYield.CheckoutService',
    );

    final dynamic response;
    try {
      response = await supabase.rpc(
        'place_checkout',
        params: {
          'p_request_id': requestId ?? _uuid.v4(),
          'p_cart_items': items
              .map(
                (item) => {
                  'id': item.cartItemId,
                  'quantity_kg': item.quantityKg,
                },
              )
              .toList(),
          'p_payment_method': paymentMethod,
          if (paymentMethod == 'card' && linkedCardId != null)
            'p_linked_card_id': linkedCardId,
          'p_delivery_address': buyerProfile.address.isEmpty
              ? null
              : buyerProfile.address.toMap(),
          'p_order_date':
              '${orderDate.year.toString().padLeft(4, '0')}-'
              '${orderDate.month.toString().padLeft(2, '0')}-'
              '${orderDate.day.toString().padLeft(2, '0')}',
        },
      );
    } on PostgrestException catch (error) {
      throw _mapCheckoutError(error);
    }

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
      paymentMethod:
          (result['payment'] as Map?)?['method'] as String? ?? paymentMethod,
      cardLast4: (result['payment'] as Map?)?['card_last4'] as String?,
      cardBrand: (result['payment'] as Map?)?['card_brand'] as String?,
    );
  }

  /// Known payment codes (declines, low wallet balance, card problems) become a
  /// [PaymentException] with a localized message; anything else passes through.
  Object _mapCheckoutError(PostgrestException error) {
    final mapped = PaymentException.fromServerMessage(error.message);
    return mapped.code == 'unknown' ? error : mapped;
  }

  /// PowerSync writes are queued locally and may not have reached Postgres
  /// when the buyer confirms checkout. The checkout RPC runs against the
  /// server cart, so mirror the local cart first to avoid a false "Cart not
  /// found" error when the app is online.
  Future<void> _ensureServerCart({
    required String buyerProfileId,
    required Set<String> cartItemIds,
  }) async {
    final cart = await db.getOptional(
      'SELECT id, created_at, updated_at FROM cart '
      'WHERE buyer_profile_id = ?',
      [buyerProfileId],
    );
    if (cart == null) {
      throw StateError('Local cart not found');
    }

    final localCartId = cart['id'] as String;
    final serverCart = await supabase
        .from('cart')
        .select('id')
        .eq('buyer_profile_id', buyerProfileId)
        .maybeSingle();
    final cartId = serverCart?['id'] as String? ?? localCartId;

    if (serverCart == null) {
      await supabase.from('cart').insert({
        'id': cartId,
        'buyer_profile_id': buyerProfileId,
        'created_at': cart['created_at'],
        'updated_at': cart['updated_at'],
      });
    }

    final localItems = await db.getAll(
      'SELECT id, produce_listing_id, quantity_kg, created_at, updated_at '
      'FROM cart_item WHERE cart_id = ?',
      [localCartId],
    );
    final selectedItems = localItems.where(
      (item) => cartItemIds.contains(item['id'] as String),
    );

    for (final item in selectedItems) {
      await supabase.from('cart_item').upsert({
        'id': item['id'],
        'cart_id': cartId,
        'produce_listing_id': item['produce_listing_id'],
        'quantity_kg': item['quantity_kg'],
        'created_at': item['created_at'],
        'updated_at': item['updated_at'],
      });
    }
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

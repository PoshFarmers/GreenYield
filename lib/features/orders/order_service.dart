import 'dart:convert';
import 'dart:developer' as developer;

import '../../core/local_db/powersync.dart';
import '../../core/supabase/client.dart';
import 'order_detail_models.dart';

/// Sprint 3 — Task: Multi-Role Order Management.
///
/// Reads come from the PowerSync local SQLite mirror (offline-first,
/// real-time via PowerSync sync). Writes (status transitions) call
/// Supabase RPCs which then propagate back via PowerSync replication.
///
/// PowerSync local tables available:
///   orders, order_item, delivery, delivery_assignment, vehicle
/// Profile names are only available for the current user's own profile
/// row (RLS), so buyer/farmer names are read from the `delivery` row's
/// denormalized display-name columns where possible, and from the
/// current user's profile for their own role.
class OrderService {
  const OrderService();

  static final Map<String, String> _firstImageUrlCache = {};

  Future<List<OrderSummary>> _enrichOrderSummaries(
    List<OrderSummary> orders,
  ) async {
    final result = <OrderSummary>[];
    for (final order in orders) {
      if (_firstImageUrlCache.containsKey(order.id)) {
        result.add(
          order.copyWith(firstImageUrl: _firstImageUrlCache[order.id]),
        );
      } else {
        String? resolvedImg;
        try {
          final detail = await fetchOrderDetailFromServer(order.id);
          if (detail != null && detail.items.isNotEmpty) {
            final img = detail.items.first.imageUrl;
            if (img != null && img.isNotEmpty) {
              resolvedImg = img;
            }
          }
        } catch (_) {}

        resolvedImg ??= order.firstImageUrl;
        if (resolvedImg != null && resolvedImg.isNotEmpty) {
          _firstImageUrlCache[order.id] = resolvedImg;
        }
        result.add(order.copyWith(firstImageUrl: resolvedImg));
      }
    }
    return result;
  }

  Future<List<DeliverySummary>> _enrichDeliverySummaries(
    List<DeliverySummary> deliveries,
  ) async {
    final result = <DeliverySummary>[];
    for (final d in deliveries) {
      final order = d.order;
      if (_firstImageUrlCache.containsKey(order.id)) {
        final newOrder = order.copyWith(
          firstImageUrl: _firstImageUrlCache[order.id],
        );
        result.add(
          DeliverySummary(
            deliveryId: d.deliveryId,
            deliveryStatus: d.deliveryStatus,
            farmerDisplayName: d.farmerDisplayName,
            buyerDisplayName: d.buyerDisplayName,
            assignedAt: d.assignedAt,
            pickedUpAt: d.pickedUpAt,
            deliveredAt: d.deliveredAt,
            order: newOrder,
          ),
        );
      } else {
        String? resolvedImg;
        try {
          final detail = await fetchOrderDetailFromServer(order.id);
          if (detail != null && detail.items.isNotEmpty) {
            final img = detail.items.first.imageUrl;
            if (img != null && img.isNotEmpty) {
              resolvedImg = img;
            }
          }
        } catch (_) {}

        resolvedImg ??= order.firstImageUrl;
        if (resolvedImg != null && resolvedImg.isNotEmpty) {
          _firstImageUrlCache[order.id] = resolvedImg;
        }
        final newOrder = order.copyWith(firstImageUrl: resolvedImg);
        result.add(
          DeliverySummary(
            deliveryId: d.deliveryId,
            deliveryStatus: d.deliveryStatus,
            farmerDisplayName: d.farmerDisplayName,
            buyerDisplayName: d.buyerDisplayName,
            assignedAt: d.assignedAt,
            pickedUpAt: d.pickedUpAt,
            deliveredAt: d.deliveredAt,
            order: newOrder,
          ),
        );
      }
    }
    return result;
  }

  // =========================================================================
  // Stream queries — PowerSync local mirror
  // =========================================================================

  /// Buyer: watch orders filtered by [statuses], newest first.
  Stream<List<OrderSummary>> watchOrdersForBuyer({
    required String buyerProfileId,
    required List<String> statuses,
  }) {
    final placeholders = List.filled(statuses.length, '?').join(', ');
    return db
        .watch(
          '''
          SELECT
            o.id AS id,
            o.checkout_group_id,
            o.status,
            o.total_amount,
            o.placed_at,
            o.order_date,
            o.delivery_id,
            (SELECT SUM(quantity_kg) FROM order_item oi WHERE oi.order_id = o.id) AS total_quantity,
            COALESCE(p_farmer.first_name || ' ' || p_farmer.last_name, d.farmer_display_name) AS counterpart_name,
            (
              SELECT GROUP_CONCAT(oi2.crop_name, ', ')
              FROM (
                SELECT c.name AS crop_name
                FROM order_item oi
                JOIN crop c ON c.id = oi.crop_id
                WHERE oi.order_id = o.id
                LIMIT 3
              ) oi2
            ) AS crop_names,
            (
              SELECT COALESCE(pl.image_url, fc.image_url, c.fallback_image_url)
              FROM order_item oi
              JOIN crop c ON c.id = oi.crop_id
              LEFT JOIN produce_listing pl ON pl.id = oi.produce_listing_id
              LEFT JOIN farmer_crop fc ON fc.farmer_profile_id = o.farmer_profile_id AND fc.crop_id = oi.crop_id
              WHERE oi.order_id = o.id
              LIMIT 1
            ) AS first_image_url
          FROM orders o
          LEFT JOIN delivery d ON d.order_id = o.id
          LEFT JOIN profile p_farmer ON p_farmer.id = o.farmer_profile_id
          WHERE o.buyer_profile_id = ?
            AND o.status IN ($placeholders)
          ORDER BY o.placed_at DESC
          ''',
          parameters: [buyerProfileId, ...statuses],
        )
        .map((rows) => rows.map(OrderSummary.fromMap).toList())
        .asyncMap(_enrichOrderSummaries);
  }

  /// Farmer: watch orders filtered by [statuses], newest first.
  Stream<List<OrderSummary>> watchOrdersForFarmer({
    required String farmerProfileId,
    required List<String> statuses,
  }) {
    final placeholders = List.filled(statuses.length, '?').join(', ');
    return db
        .watch(
          '''
          SELECT
            o.id AS id,
            o.checkout_group_id,
            o.status,
            o.total_amount,
            o.placed_at,
            o.order_date,
            o.delivery_id,
            (SELECT SUM(quantity_kg) FROM order_item oi WHERE oi.order_id = o.id) AS total_quantity,
            COALESCE(p_buyer.first_name || ' ' || p_buyer.last_name, d.buyer_display_name) AS counterpart_name,
            (
              SELECT GROUP_CONCAT(oi2.crop_name, ', ')
              FROM (
                SELECT c.name AS crop_name
                FROM order_item oi
                JOIN crop c ON c.id = oi.crop_id
                WHERE oi.order_id = o.id
                LIMIT 3
              ) oi2
            ) AS crop_names,
            (
              SELECT COALESCE(pl.image_url, fc.image_url, c.fallback_image_url)
              FROM order_item oi
              JOIN crop c ON c.id = oi.crop_id
              LEFT JOIN produce_listing pl ON pl.id = oi.produce_listing_id
              LEFT JOIN farmer_crop fc ON fc.farmer_profile_id = o.farmer_profile_id AND fc.crop_id = oi.crop_id
              WHERE oi.order_id = o.id
              LIMIT 1
            ) AS first_image_url
          FROM orders o
          LEFT JOIN delivery d ON d.order_id = o.id
          LEFT JOIN profile p_buyer ON p_buyer.id = o.buyer_profile_id
          WHERE o.farmer_profile_id = ?
            AND o.status IN ($placeholders)
          ORDER BY o.placed_at DESC
          ''',
          parameters: [farmerProfileId, ...statuses],
        )
        .map((rows) => rows.map(OrderSummary.fromMap).toList())
        .asyncMap(_enrichOrderSummaries);
  }

  /// Driver: watch deliveries filtered by [deliveryStatuses], newest first.
  /// The joined order's status is exposed as `order_status` so the detail
  /// screen can render role-specific action buttons correctly.
  Stream<List<DeliverySummary>> watchDeliveriesForDriver({
    required String driverProfileId,
    required List<String> deliveryStatuses,
  }) {
    final placeholders = List.filled(deliveryStatuses.length, '?').join(', ');
    return db
        .watch(
          '''
          SELECT
            d.id           AS delivery_id,
            d.status       AS delivery_status,
            COALESCE(p_farmer.first_name || ' ' || p_farmer.last_name, d.farmer_display_name) AS farmer_display_name,
            COALESCE(p_buyer.first_name || ' ' || p_buyer.last_name, d.buyer_display_name) AS buyer_display_name,
            d.assigned_at,
            d.picked_up_at,
            d.delivered_at,
            o.id           AS order_id,
            o.checkout_group_id,
            o.status       AS order_status,
            o.total_amount,
            o.placed_at,
            o.order_date,
            (SELECT SUM(quantity_kg) FROM order_item oi WHERE oi.order_id = o.id) AS total_quantity,
            (
              SELECT GROUP_CONCAT(oi2.crop_name, ', ')
              FROM (
                SELECT c.name AS crop_name
                FROM order_item oi
                JOIN crop c ON c.id = oi.crop_id
                WHERE oi.order_id = o.id
                LIMIT 3
              ) oi2
            ) AS crop_names,
            (
              SELECT COALESCE(pl.image_url, fc.image_url, c.fallback_image_url)
              FROM order_item oi
              JOIN crop c ON c.id = oi.crop_id
              LEFT JOIN produce_listing pl ON pl.id = oi.produce_listing_id
              LEFT JOIN farmer_crop fc ON fc.farmer_profile_id = o.farmer_profile_id AND fc.crop_id = oi.crop_id
              WHERE oi.order_id = o.id
              LIMIT 1
            ) AS first_image_url
          FROM delivery d
          JOIN delivery_assignment da
               ON da.delivery_id = d.id AND da.is_current = 1
          JOIN orders o ON o.id = d.order_id
          LEFT JOIN profile p_farmer ON p_farmer.id = o.farmer_profile_id
          LEFT JOIN profile p_buyer ON p_buyer.id = o.buyer_profile_id
          WHERE da.driver_profile_id = ?
            AND d.status IN ($placeholders)
          ORDER BY d.assigned_at DESC
          ''',
          parameters: [driverProfileId, ...deliveryStatuses],
        )
        .map((rows) => rows.map(DeliverySummary.fromMap).toList())
        .asyncMap(_enrichDeliverySummaries);
  }

  /// Watch the full detail of a single order.
  ///
  /// The local PowerSync SQLite only replicates the *current user's* profile
  /// row (RLS: `profile.id = auth.uid()`), so JOINing p_farmer / p_buyer /
  /// p_driver from the local DB always returns null for cross-user rows.
  ///
  /// Strategy:
  ///   1. Watch the local `orders` table so the stream fires whenever the
  ///      order status changes (real-time, offline-first).
  ///   2. On each emission, call the SECURITY DEFINER RPC `get_order_detail`
  ///      on Supabase to get the enriched data (participant names, phones,
  ///      item images) that require cross-user profile reads.
  Stream<OrderDetail?> watchOrderDetail(String orderId) {
    return db
        .watch(
          'SELECT id, status FROM orders WHERE id = ? LIMIT 1',
          parameters: [orderId],
        )
        .asyncMap((rows) async {
          if (rows.isEmpty) return null;
          try {
            return await fetchOrderDetailFromServer(orderId);
          } catch (e) {
            developer.log(
              'get_order_detail RPC failed, falling back to local: $e',
              name: 'GreenYield.OrderService',
            );
            return _fetchOrderDetailLocally(orderId);
          }
        });
  }

  /// Calls the `get_order_detail` SECURITY DEFINER RPC on Supabase.
  /// This can read all profiles, delivery display names, and item images
  /// regardless of PowerSync sync rules.
  Future<OrderDetail?> fetchOrderDetailFromServer(String orderId) async {
    final data = await supabase.rpc(
      'get_order_detail',
      params: {'p_order_id': orderId},
    );

    if (data == null) return null;
    final row = data as Map<String, dynamic>;

    final items = (row['items'] as List<dynamic>? ?? [])
        .map((e) => OrderItemDetail.fromMap(e as Map<String, dynamic>))
        .toList();

    final farmerName = (row['farmer_name'] as String? ?? '').trim();
    final buyerName = (row['buyer_name'] as String? ?? '').trim();
    final driverName = row['driver_name'] as String?;

    return OrderDetail(
      id: row['id'] as String,
      checkoutGroupId: row['checkout_group_id'] as String,
      status: OrderStatus.fromDb(row['status'] as String?),
      placedAt: _parseDateTime(row['placed_at']),
      orderDate: row['order_date'] != null
          ? DateTime.tryParse(row['order_date'] as String)
          : null,
      subtotalAmount: _toDouble(row['subtotal_amount']),
      deliveryFeeAmount: _toDouble(row['delivery_fee_amount']),
      totalAmount: _toDouble(row['total_amount']),
      items: items,
      buyerProfileId: row['buyer_profile_id'] as String,
      buyerName: buyerName.isNotEmpty ? buyerName : 'Buyer',
      buyerPhone: row['buyer_phone'] as String?,
      buyerAddress: _parseAddress(row['delivery_address']),
      farmerProfileId: row['farmer_profile_id'] as String,
      farmerName: farmerName.isNotEmpty ? farmerName : 'Farmer',
      farmerPhone: row['farmer_phone'] as String?,
      farmerAddress: null, // not included in RPC yet
      deliveryId: row['delivery_id'] as String?,
      deliveryStatus: row['delivery_status'] != null
          ? DeliveryStatus.fromDb(row['delivery_status'] as String)
          : null,
      driverProfileId: row['driver_profile_id'] as String?,
      driverName: driverName,
      driverPhone: row['driver_phone'] as String?,
      vehicleType: row['vehicle_type'] as String?,
      vehiclePlate: row['vehicle_plate'] as String?,
      farmerDisplayName: farmerName.isNotEmpty ? farmerName : null,
      buyerDisplayName: buyerName.isNotEmpty ? buyerName : null,
    );
  }

  /// Local SQLite fallback used when the Supabase RPC is unavailable (offline).
  Future<OrderDetail?> _fetchOrderDetailLocally(String orderId) async {
    final rows = await db.getAll(
      '''
      SELECT
        o.id AS id,
        o.checkout_group_id,
        o.status,
        o.buyer_profile_id,
        o.farmer_profile_id,
        o.subtotal_amount,
        o.delivery_fee_amount,
        o.total_amount,
        o.placed_at,
        o.order_date,
        o.delivery_address,
        d.id              AS delivery_id,
        d.status          AS delivery_status,
        COALESCE(p_farmer.first_name || ' ' || p_farmer.last_name, d.farmer_display_name) AS farmer_display_name,
        COALESCE(p_buyer.first_name  || ' ' || p_buyer.last_name,  d.buyer_display_name)  AS buyer_display_name,
        da.driver_profile_id,
        COALESCE(p_driver.first_name || ' ' || p_driver.last_name, NULL) AS driver_display_name,
        p_driver.phone    AS driver_phone,
        p_farmer.phone    AS farmer_phone,
        p_buyer.phone     AS buyer_phone,
        v.vehicle_type,
        v.plate_number    AS vehicle_plate
      FROM orders o
      LEFT JOIN delivery d ON d.order_id = o.id
      LEFT JOIN profile p_farmer ON p_farmer.id = o.farmer_profile_id
      LEFT JOIN profile p_buyer  ON p_buyer.id  = o.buyer_profile_id
      LEFT JOIN delivery_assignment da
                ON da.delivery_id = d.id AND da.is_current = 1
      LEFT JOIN profile p_driver ON p_driver.id = da.driver_profile_id
      LEFT JOIN vehicle v ON v.driver_profile_id = da.driver_profile_id
      WHERE o.id = ?
      LIMIT 1
      ''',
      [orderId],
    );

    if (rows.isEmpty) return null;
    final row = rows.first;

    final itemRows = await db.getAll(
      '''
      SELECT oi.id, oi.crop_id, oi.quantity_kg, oi.price_per_kg,
             c.name AS crop_name,
             pl.image_url
      FROM order_item oi
      JOIN crop c ON c.id = oi.crop_id
      LEFT JOIN produce_listing pl ON pl.id = oi.produce_listing_id
      WHERE oi.order_id = ?
      ORDER BY oi.created_at ASC
      ''',
      [orderId],
    );

    final items = itemRows.map(OrderItemDetail.fromMap).toList();
    final buyerDisplayName = row['buyer_display_name'] as String?;
    final farmerDisplayName = row['farmer_display_name'] as String?;

    return OrderDetail(
      id: row['id'] as String,
      checkoutGroupId: row['checkout_group_id'] as String,
      status: OrderStatus.fromDb(row['status'] as String?),
      placedAt: _parseDateTime(row['placed_at']),
      orderDate: row['order_date'] != null
          ? DateTime.tryParse(row['order_date'] as String)
          : null,
      subtotalAmount: _toDouble(row['subtotal_amount']),
      deliveryFeeAmount: _toDouble(row['delivery_fee_amount']),
      totalAmount: _toDouble(row['total_amount']),
      items: items,
      buyerProfileId: row['buyer_profile_id'] as String,
      buyerName: buyerDisplayName ?? 'Buyer',
      buyerPhone: row['buyer_phone'] as String?,
      buyerAddress: _parseAddress(row['delivery_address']),
      farmerProfileId: row['farmer_profile_id'] as String,
      farmerName: farmerDisplayName ?? 'Farmer',
      farmerPhone: row['farmer_phone'] as String?,
      farmerAddress: null,
      deliveryId: row['delivery_id'] as String?,
      deliveryStatus: row['delivery_status'] != null
          ? DeliveryStatus.fromDb(row['delivery_status'] as String)
          : null,
      driverProfileId: row['driver_profile_id'] as String?,
      driverName: row['driver_display_name'] as String?,
      driverPhone: row['driver_phone'] as String?,
      vehicleType: row['vehicle_type'] as String?,
      vehiclePlate: row['vehicle_plate'] as String?,
      farmerDisplayName: farmerDisplayName,
      buyerDisplayName: buyerDisplayName,
    );
  }

  // =========================================================================
  // RPC calls — Supabase
  // =========================================================================

  /// Farmer marks the order as packed. Calls `mark_order_packed(p_order_id)`.
  Future<void> markOrderPacked(String orderId) async {
    developer.log(
      'Calling mark_order_packed RPC — order: $orderId',
      name: 'GreenYield.OrderService',
    );
    await supabase.rpc('mark_order_packed', params: {'p_order_id': orderId});
  }

  /// Driver confirms pickup. Calls `transition_delivery_status`.
  Future<void> confirmPickup(String deliveryId) async {
    developer.log(
      'Calling transition_delivery_status → picked_up — delivery: $deliveryId',
      name: 'GreenYield.OrderService',
    );
    await supabase.rpc(
      'transition_delivery_status',
      params: {'p_delivery_id': deliveryId, 'p_new_status': 'picked_up'},
    );
  }

  /// Driver marks as in-transit. Calls `transition_delivery_status`.
  Future<void> markInTransit(String deliveryId) async {
    developer.log(
      'Calling transition_delivery_status → in_transit — delivery: $deliveryId',
      name: 'GreenYield.OrderService',
    );
    await supabase.rpc(
      'transition_delivery_status',
      params: {'p_delivery_id': deliveryId, 'p_new_status': 'in_transit'},
    );
  }

  /// Driver marks as delivered. Calls `transition_delivery_status`.
  Future<void> markDelivered(String deliveryId) async {
    developer.log(
      'Calling transition_delivery_status → delivered — delivery: $deliveryId',
      name: 'GreenYield.OrderService',
    );
    await supabase.rpc(
      'transition_delivery_status',
      params: {'p_delivery_id': deliveryId, 'p_new_status': 'delivered'},
    );
  }

  /// Buyer or driver cancels an order. Calls `cancel_order(p_order_id)`.
  Future<void> cancelOrder(String orderId, {String? note}) async {
    developer.log(
      'Calling cancel_order RPC — order: $orderId',
      name: 'GreenYield.OrderService',
    );
    await supabase.rpc(
      'cancel_order',
      params: {'p_order_id': orderId, if (note != null) 'p_note': note},
    );
  }
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

double _toDouble(dynamic value) {
  if (value == null) return 0.0;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0.0;
  return 0.0;
}

DateTime _parseDateTime(dynamic value) {
  if (value == null) return DateTime.now();
  if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
  return DateTime.now();
}

String? _parseAddress(dynamic value) {
  if (value == null) return null;
  final str = value is String ? value : value.toString();
  if (str.isEmpty) return null;
  try {
    // delivery_address may be stored as a JSON string {"line1":..., "city":...}
    // or as a plain text string. Try JSON first, then return as-is.
    final decoded = jsonDecode(str);
    if (decoded is Map) {
      final parts = [
        decoded['line1'],
        decoded['line2'],
        decoded['city'],
        decoded['postal_code'],
      ].where((p) => p != null && (p as String).isNotEmpty).toList();
      return parts.isEmpty ? null : parts.join(', ');
    }
  } catch (_) {
    // Not valid JSON — return the raw string as-is if it's a plain address.
    if (str.startsWith('{')) return null; // malformed JSON, discard
    return str;
  }
  return null;
}

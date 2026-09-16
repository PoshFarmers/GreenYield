// ---------------------------------------------------------------------------
// ENUMs — mirrors Postgres order_status and delivery_status ENUMs exactly.
// ---------------------------------------------------------------------------

enum OrderStatus {
  placed,
  confirmed,
  assigned,
  packed,
  pickedUp,
  inTransit,
  delivered,
  completed,
  cancelled;

  static OrderStatus fromDb(String? value) {
    switch (value) {
      case 'placed':
        return OrderStatus.placed;
      case 'confirmed':
        return OrderStatus.confirmed;
      case 'assigned':
        return OrderStatus.assigned;
      case 'packed':
        return OrderStatus.packed;
      case 'picked_up':
        return OrderStatus.pickedUp;
      case 'in_transit':
        return OrderStatus.inTransit;
      case 'delivered':
        return OrderStatus.delivered;
      case 'completed':
        return OrderStatus.completed;
      case 'cancelled':
        return OrderStatus.cancelled;
      default:
        return OrderStatus.placed;
    }
  }

  String toDb() {
    switch (this) {
      case OrderStatus.placed:
        return 'placed';
      case OrderStatus.confirmed:
        return 'confirmed';
      case OrderStatus.assigned:
        return 'assigned';
      case OrderStatus.packed:
        return 'packed';
      case OrderStatus.pickedUp:
        return 'picked_up';
      case OrderStatus.inTransit:
        return 'in_transit';
      case OrderStatus.delivered:
        return 'delivered';
      case OrderStatus.completed:
        return 'completed';
      case OrderStatus.cancelled:
        return 'cancelled';
    }
  }

  String get displayLabel {
    switch (this) {
      case OrderStatus.placed:
        return 'Placed';
      case OrderStatus.confirmed:
        return 'Confirmed';
      case OrderStatus.assigned:
        return 'Assigned';
      case OrderStatus.packed:
        return 'Packed';
      case OrderStatus.pickedUp:
        return 'Picked Up';
      case OrderStatus.inTransit:
        return 'On The Way';
      case OrderStatus.delivered:
        return 'Completed';
      case OrderStatus.completed:
        return 'Completed';
      case OrderStatus.cancelled:
        return 'Cancelled';
    }
  }

  bool get isActive =>
      this == OrderStatus.placed ||
      this == OrderStatus.confirmed ||
      this == OrderStatus.assigned ||
      this == OrderStatus.packed ||
      this == OrderStatus.pickedUp ||
      this == OrderStatus.inTransit;

  bool get isTerminal =>
      this == OrderStatus.delivered ||
      this == OrderStatus.completed ||
      this == OrderStatus.cancelled;

  bool get isCancellable =>
      this == OrderStatus.placed ||
      this == OrderStatus.confirmed ||
      this == OrderStatus.assigned ||
      this == OrderStatus.packed;
}

enum DeliveryStatus {
  unassigned,
  assigned,
  pickedUp,
  inTransit,
  delivered;

  static DeliveryStatus fromDb(String? value) {
    switch (value) {
      case 'unassigned':
        return DeliveryStatus.unassigned;
      case 'assigned':
        return DeliveryStatus.assigned;
      case 'picked_up':
        return DeliveryStatus.pickedUp;
      case 'in_transit':
        return DeliveryStatus.inTransit;
      case 'delivered':
        return DeliveryStatus.delivered;
      default:
        return DeliveryStatus.unassigned;
    }
  }

  String toDb() {
    switch (this) {
      case DeliveryStatus.unassigned:
        return 'unassigned';
      case DeliveryStatus.assigned:
        return 'assigned';
      case DeliveryStatus.pickedUp:
        return 'picked_up';
      case DeliveryStatus.inTransit:
        return 'in_transit';
      case DeliveryStatus.delivered:
        return 'delivered';
    }
  }
}

// ---------------------------------------------------------------------------
// Lightweight list-row models used by the tab lists.
// ---------------------------------------------------------------------------

/// One row in a buyer's or farmer's order list.
class OrderSummary {
  final String id;
  final String checkoutGroupId;
  final OrderStatus status;

  /// Farmer display name (for buyer view) or buyer display name (for farmer view).
  final String? counterpartName;
  final List<String> cropNames;
  final double totalAmount;
  final double totalQuantity;
  final DateTime placedAt;
  final DateTime? orderDate;

  /// delivery_id — present once a delivery row exists server-side.
  final String? deliveryId;

  /// Optional thumbnail of the first item
  final String? firstImageUrl;

  const OrderSummary({
    required this.id,
    required this.checkoutGroupId,
    required this.status,
    this.counterpartName,
    this.cropNames = const [],
    required this.totalAmount,
    this.totalQuantity = 0.0,
    required this.placedAt,
    this.orderDate,
    this.deliveryId,
    this.firstImageUrl,
  });

  /// Short human-readable order id: GY-XXXXXX
  String get displayId =>
      'GY-${id.replaceAll('-', '').substring(0, 6).toUpperCase()}';

  factory OrderSummary.fromMap(Map<String, dynamic> row) {
    return OrderSummary(
      id: row['id'] as String,
      checkoutGroupId: row['checkout_group_id'] as String,
      status: OrderStatus.fromDb(row['status'] as String?),
      counterpartName: row['counterpart_name'] as String?,
      cropNames: _parseCropNames(row['crop_names']),
      totalAmount: _toDouble(row['total_amount']),
      totalQuantity: _toDouble(row['total_quantity']),
      placedAt: _parseDateTime(row['placed_at']),
      orderDate: row['order_date'] != null
          ? DateTime.tryParse(row['order_date'] as String)
          : null,
      deliveryId: row['delivery_id'] as String?,
      firstImageUrl: row['first_image_url'] as String?,
    );
  }

  OrderSummary copyWith({
    String? id,
    String? checkoutGroupId,
    OrderStatus? status,
    String? counterpartName,
    List<String>? cropNames,
    double? totalAmount,
    double? totalQuantity,
    DateTime? placedAt,
    DateTime? orderDate,
    String? deliveryId,
    String? firstImageUrl,
  }) {
    return OrderSummary(
      id: id ?? this.id,
      checkoutGroupId: checkoutGroupId ?? this.checkoutGroupId,
      status: status ?? this.status,
      counterpartName: counterpartName ?? this.counterpartName,
      cropNames: cropNames ?? this.cropNames,
      totalAmount: totalAmount ?? this.totalAmount,
      totalQuantity: totalQuantity ?? this.totalQuantity,
      placedAt: placedAt ?? this.placedAt,
      orderDate: orderDate ?? this.orderDate,
      deliveryId: deliveryId ?? this.deliveryId,
      firstImageUrl: firstImageUrl ?? this.firstImageUrl,
    );
  }

  static List<String> _parseCropNames(dynamic raw) {
    if (raw == null) return [];
    if (raw is String && raw.isNotEmpty) {
      // Stored as comma-separated from the GROUP_CONCAT / string_agg query.
      return raw.split(',').map((s) => s.trim()).toList();
    }
    return [];
  }
}

/// One row in a driver's delivery list.
class DeliverySummary {
  final String deliveryId;
  final DeliveryStatus deliveryStatus;
  final String? farmerDisplayName;
  final String? buyerDisplayName;
  final DateTime? assignedAt;
  final DateTime? pickedUpAt;
  final DateTime? deliveredAt;

  /// The underlying order details.
  final OrderSummary order;

  const DeliverySummary({
    required this.deliveryId,
    required this.deliveryStatus,
    this.farmerDisplayName,
    this.buyerDisplayName,
    this.assignedAt,
    this.pickedUpAt,
    this.deliveredAt,
    required this.order,
  });

  factory DeliverySummary.fromMap(Map<String, dynamic> row) {
    return DeliverySummary(
      deliveryId: row['delivery_id'] as String,
      deliveryStatus: DeliveryStatus.fromDb(row['delivery_status'] as String?),
      farmerDisplayName: row['farmer_display_name'] as String?,
      buyerDisplayName: row['buyer_display_name'] as String?,
      assignedAt: row['assigned_at'] != null
          ? DateTime.tryParse(row['assigned_at'] as String)
          : null,
      pickedUpAt: row['picked_up_at'] != null
          ? DateTime.tryParse(row['picked_up_at'] as String)
          : null,
      deliveredAt: row['delivered_at'] != null
          ? DateTime.tryParse(row['delivered_at'] as String)
          : null,
      order: OrderSummary(
        id: row['order_id'] as String,
        checkoutGroupId: row['checkout_group_id'] as String,
        status: OrderStatus.fromDb(row['order_status'] as String?),
        cropNames: OrderSummary._parseCropNames(row['crop_names']),
        totalAmount: _toDouble(row['total_amount']),
        placedAt: _parseDateTime(row['placed_at']),
        orderDate: row['order_date'] != null
            ? DateTime.tryParse(row['order_date'] as String)
            : null,
        deliveryId: row['delivery_id'] as String?,
        firstImageUrl: row['first_image_url'] as String?,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Full detail model — used by OrderDetailScreen.
// ---------------------------------------------------------------------------

class OrderItemDetail {
  final String id;
  final String cropId;
  final String cropName;
  final String? imageUrl;
  final double quantityKg;
  final double pricePerKg;

  const OrderItemDetail({
    required this.id,
    required this.cropId,
    required this.cropName,
    this.imageUrl,
    required this.quantityKg,
    required this.pricePerKg,
  });

  double get lineTotal => quantityKg * pricePerKg;

  factory OrderItemDetail.fromMap(Map<String, dynamic> row) {
    return OrderItemDetail(
      id: row['id'] as String,
      cropId: row['crop_id'] as String,
      cropName: row['crop_name'] as String? ?? '',
      imageUrl: row['image_url'] as String?,
      quantityKg: _toDouble(row['quantity_kg']),
      pricePerKg: _toDouble(row['price_per_kg']),
    );
  }
}

/// Full order data for the detail screen.
class OrderDetail {
  final String id;
  final String checkoutGroupId;
  final OrderStatus status;
  final DateTime placedAt;
  final DateTime? orderDate;

  // Financial
  final double subtotalAmount;
  final double deliveryFeeAmount;
  final double totalAmount;

  // Items
  final List<OrderItemDetail> items;

  // Buyer info (from profile — only locally cached fields)
  final String buyerProfileId;
  final String buyerName;
  final String? buyerPhone;
  final String? buyerAddress;

  // Farmer info
  final String farmerProfileId;
  final String farmerName;
  final String? farmerPhone;
  final String? farmerAddress;

  // Driver / delivery info (nullable — not always assigned)
  final String? deliveryId;
  final DeliveryStatus? deliveryStatus;
  final String? driverProfileId;
  final String? driverName;
  final String? driverPhone;
  final String? vehicleType;
  final String? vehiclePlate;

  // Cached display names from delivery row
  final String? farmerDisplayName;
  final String? buyerDisplayName;

  const OrderDetail({
    required this.id,
    required this.checkoutGroupId,
    required this.status,
    required this.placedAt,
    this.orderDate,
    required this.subtotalAmount,
    required this.deliveryFeeAmount,
    required this.totalAmount,
    required this.items,
    required this.buyerProfileId,
    required this.buyerName,
    this.buyerPhone,
    this.buyerAddress,
    required this.farmerProfileId,
    required this.farmerName,
    this.farmerPhone,
    this.farmerAddress,
    this.deliveryId,
    this.deliveryStatus,
    this.driverProfileId,
    this.driverName,
    this.driverPhone,
    this.vehicleType,
    this.vehiclePlate,
    this.farmerDisplayName,
    this.buyerDisplayName,
  });

  String get displayId =>
      'GY-${id.replaceAll('-', '').substring(0, 6).toUpperCase()}';

  /// Stepper progress: 0=Placed, 1=Packed, 2=OnTheWay, 3=Delivered
  int get stepperIndex {
    switch (status) {
      case OrderStatus.placed:
      case OrderStatus.confirmed:
      case OrderStatus.assigned:
        return 0;
      case OrderStatus.packed:
        return 1;
      case OrderStatus.pickedUp:
      case OrderStatus.inTransit:
        return 2;
      case OrderStatus.delivered:
      case OrderStatus.completed:
        return 3;
      case OrderStatus.cancelled:
        return -1;
    }
  }
}

// ---------------------------------------------------------------------------
// Shared helpers
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

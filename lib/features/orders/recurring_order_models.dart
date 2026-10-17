import 'dart:convert';

class RecurringSchedule {
  final String id;
  final String buyerProfileId;
  final String label;
  final String status;
  final DateTime createdAt;
  final DateTime? endDate;

  const RecurringSchedule({
    required this.id,
    required this.buyerProfileId,
    required this.label,
    required this.status,
    required this.createdAt,
    this.endDate,
  });

  factory RecurringSchedule.fromMap(Map<String, dynamic> map) {
    return RecurringSchedule(
      id: map['id'] as String,
      buyerProfileId: map['buyer_profile_id'] as String,
      label: map['label'] as String,
      status: map['status'] as String,
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
      endDate: map['end_date'] != null
          ? DateTime.parse(map['end_date'] as String).toLocal()
          : null,
    );
  }

  Map<String, dynamic> toInsertMap() => {
    'buyer_profile_id': buyerProfileId,
    'label': label,
    'status': status,
    'created_at': createdAt.toUtc().toIso8601String(),
    if (endDate != null) 'end_date': endDate!.toUtc().toIso8601String(),
  };
}

class RecurringScheduleSummary {
  final RecurringSchedule schedule;
  final List<int> daysOfWeek;
  final int totalItems;

  const RecurringScheduleSummary({
    required this.schedule,
    required this.daysOfWeek,
    required this.totalItems,
  });
}

class RecurringOrder {
  final String id;
  final String scheduleId;
  final String frequency; // 'weekly' | 'biweekly' | 'monthly'
  final int dayOfWeek; // 0 = Sunday
  final DateTime nextRunAt;
  final Map<String, dynamic>? deliveryAddress;
  final String? deliveryLocation;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  const RecurringOrder({
    required this.id,
    required this.scheduleId,
    required this.frequency,
    required this.dayOfWeek,
    required this.nextRunAt,
    this.deliveryAddress,
    this.deliveryLocation,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory RecurringOrder.fromMap(Map<String, dynamic> map) {
    String? location;
    if (map['delivery_location'] != null) {
      location = map['delivery_location'] as String;
    }

    return RecurringOrder(
      id: map['id'] as String,
      scheduleId: map['schedule_id'] as String,
      frequency: map['frequency'] as String,
      dayOfWeek: map['day_of_week'] as int,
      nextRunAt: DateTime.parse(map['next_run_at'] as String).toLocal(),
      deliveryAddress: map['delivery_address'] != null
          ? (map['delivery_address'] is String
                ? jsonDecode(map['delivery_address'] as String)
                : map['delivery_address'] as Map<String, dynamic>)
          : null,
      deliveryLocation: location,
      status: map['status'] as String,
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
      updatedAt: DateTime.parse(map['updated_at'] as String).toLocal(),
    );
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'schedule_id': scheduleId,
      'frequency': frequency,
      'day_of_week': dayOfWeek,
      'next_run_at': nextRunAt.toUtc().toIso8601String(),
      if (deliveryAddress != null)
        'delivery_address': jsonEncode(deliveryAddress),
      if (deliveryLocation != null) 'delivery_location': deliveryLocation,
      'status': status,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }
}

class RecurringOrderItem {
  final String id;
  final String recurringOrderId;
  final String cropId;
  final double quantityKg;
  final String? preferredFarmerId;
  final DateTime createdAt;

  const RecurringOrderItem({
    required this.id,
    required this.recurringOrderId,
    required this.cropId,
    required this.quantityKg,
    this.preferredFarmerId,
    required this.createdAt,
  });

  factory RecurringOrderItem.fromMap(Map<String, dynamic> map) {
    return RecurringOrderItem(
      id: map['id'] as String,
      recurringOrderId: map['recurring_order_id'] as String,
      cropId: map['crop_id'] as String,
      quantityKg: (map['quantity_kg'] as num).toDouble(),
      preferredFarmerId: map['preferred_farmer_id'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
    );
  }

  Map<String, dynamic> toInsertMap() => {
    'recurring_order_id': recurringOrderId,
    'crop_id': cropId,
    'quantity_kg': quantityKg,
    if (preferredFarmerId != null) 'preferred_farmer_id': preferredFarmerId,
    'created_at': createdAt.toUtc().toIso8601String(),
  };
}

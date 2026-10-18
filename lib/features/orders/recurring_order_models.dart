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

/// One item as sent to `save_recurring_schedule`.
class RecurringItemInput {
  final String cropId;
  final double quantityKg;
  final String? preferredFarmerId;

  const RecurringItemInput({
    required this.cropId,
    required this.quantityKg,
    this.preferredFarmerId,
  });

  Map<String, dynamic> toJson() => {
    'crop_id': cropId,
    'quantity_kg': quantityKg,
    if (preferredFarmerId != null) 'preferred_farmer_id': preferredFarmerId,
  };
}

/// A delivery day of a schedule with its items (server read).
class RecurringDayDetail {
  final String recurringOrderId;
  final int dayOfWeek;
  final String frequency;
  final DateTime nextDelivery;
  final Map<String, dynamic>? deliveryAddress;
  final String status;

  /// pending | fulfilled | awaiting_funds | awaiting_inventory | cancelled
  final String processingStatus;
  final List<RecurringItemDetail> items;

  const RecurringDayDetail({
    required this.recurringOrderId,
    required this.dayOfWeek,
    required this.frequency,
    required this.nextDelivery,
    required this.deliveryAddress,
    required this.status,
    required this.processingStatus,
    required this.items,
  });

  factory RecurringDayDetail.fromMap(Map<String, dynamic> map) {
    final address = map['delivery_address'];
    return RecurringDayDetail(
      recurringOrderId: map['id'] as String,
      dayOfWeek: (map['day_of_week'] as num).toInt(),
      frequency: map['frequency'] as String? ?? 'weekly',
      nextDelivery: DateTime.parse(map['next_run_at'] as String).toLocal(),
      deliveryAddress: address is String
          ? jsonDecode(address) as Map<String, dynamic>
          : address as Map<String, dynamic>?,
      status: map['status'] as String? ?? 'active',
      processingStatus: map['processing_status'] as String? ?? 'pending',
      items: [
        for (final item in (map['recurring_order_item'] as List? ?? const []))
          RecurringItemDetail.fromMap(item as Map<String, dynamic>),
      ],
    );
  }
}

class RecurringItemDetail {
  final String cropId;
  final String cropName;
  final String? cropCategory;
  final String? fallbackImageUrl;
  final double quantityKg;
  final String? preferredFarmerId;

  const RecurringItemDetail({
    required this.cropId,
    required this.cropName,
    required this.quantityKg,
    this.cropCategory,
    this.fallbackImageUrl,
    this.preferredFarmerId,
  });

  factory RecurringItemDetail.fromMap(Map<String, dynamic> map) {
    final crop = map['crop'] as Map<String, dynamic>? ?? const {};
    return RecurringItemDetail(
      cropId: map['crop_id'] as String,
      cropName: crop['name'] as String? ?? '',
      cropCategory: crop['category'] as String?,
      fallbackImageUrl: crop['fallback_image_url'] as String?,
      quantityKg: (map['quantity_kg'] as num).toDouble(),
      preferredFarmerId: map['preferred_farmer_id'] as String?,
    );
  }
}

/// What happened to one delivery day that was due tomorrow.
class TomorrowOutcome {
  final int dayOfWeek;

  /// fulfilled | awaiting_funds | awaiting_inventory | skipped | error
  final String status;
  final String? reason;

  const TomorrowOutcome({
    required this.dayOfWeek,
    required this.status,
    this.reason,
  });
}

/// Overall result of tomorrow's orders after a save/resume, for messaging.
/// [ended]: the schedule's end date is before tomorrow, so the server
/// cancelled it on purpose — nothing will be retried.
enum TomorrowSummary { none, placed, needsFunds, needsStock, ended, failed }

class RecurringSaveResult {
  final String scheduleId;
  final List<TomorrowOutcome> tomorrow;

  const RecurringSaveResult({required this.scheduleId, required this.tomorrow});

  factory RecurringSaveResult.fromMap(Map<String, dynamic> map) {
    return RecurringSaveResult(
      scheduleId: map['schedule_id'] as String,
      tomorrow: [
        for (final row in (map['tomorrow'] as List? ?? const []))
          TomorrowOutcome(
            dayOfWeek: ((row as Map)['day_of_week'] as num).toInt(),
            status: row['status'] as String? ?? 'error',
            reason: row['reason'] as String?,
          ),
      ],
    );
  }

  /// Worst outcome wins, so the buyer always hears about a problem.
  /// `skipped` with `already_processed` counts as placed.
  TomorrowSummary get summary {
    if (tomorrow.isEmpty) return TomorrowSummary.none;
    final statuses = tomorrow.map((t) {
      if (t.status == 'skipped' && t.reason == 'already_processed') {
        return 'fulfilled';
      }
      return t.status;
    }).toSet();
    if (statuses.contains('awaiting_funds')) return TomorrowSummary.needsFunds;
    if (statuses.contains('awaiting_inventory')) {
      return TomorrowSummary.needsStock;
    }
    if (statuses.every((s) => s == 'fulfilled')) return TomorrowSummary.placed;
    if (tomorrow.any((t) => t.reason == 'schedule_expired')) {
      return TomorrowSummary.ended;
    }
    return TomorrowSummary.failed;
  }

  /// The raw server reasons for anything that wasn't placed — for logs
  /// and support, never shown to the buyer as-is.
  List<String> get problemReasons => [
    for (final t in tomorrow)
      if (t.status != 'fulfilled' &&
          !(t.status == 'skipped' && t.reason == 'already_processed'))
        '${t.status}${t.reason == null ? '' : ': ${t.reason}'}',
  ];
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

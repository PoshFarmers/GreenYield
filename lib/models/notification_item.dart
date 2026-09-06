import 'dart:convert';

/// Client-side grouping derived from `type`, since the table itself has
/// no category column. Used to drive filter chips and icon selection.
enum NotificationCategory {
  orders,
  payments,
  logistics,
  messages,
  account,
  system;

  static NotificationCategory fromType(String type) {
    if (type.startsWith('order_')) return NotificationCategory.orders;
    if (type.startsWith('payment_') || type.startsWith('refund_')) {
      return NotificationCategory.payments;
    }
    if (type.startsWith('delivery_')) return NotificationCategory.logistics;
    if (type == 'new_message') return NotificationCategory.messages;
    if (type == 'role_added' || type.startsWith('profile_')) {
      return NotificationCategory.account;
    }
    return NotificationCategory.system;
  }
}

/// Mirrors a row of the `notification` table (see
/// `20260827092248_notifications.sql` and `..._notification_events.sql`).
class NotificationItem {
  final String id;
  final String profileId;
  final String type;
  final String title;
  final String? body;
  final Map<String, dynamic> payload;
  final String? sourceTable;
  final String? sourceId;
  final DateTime? readAt;
  final DateTime createdAt;

  const NotificationItem({
    required this.id,
    required this.profileId,
    required this.type,
    required this.title,
    required this.body,
    required this.payload,
    required this.sourceTable,
    required this.sourceId,
    required this.readAt,
    required this.createdAt,
  });

  bool get isRead => readAt != null;

  NotificationCategory get category => NotificationCategory.fromType(type);

  factory NotificationItem.fromMap(Map<String, dynamic> map) {
    return NotificationItem(
      id: map['id'] as String,
      profileId: map['profile_id'] as String,
      type: map['type'] as String,
      title: map['title'] as String,
      body: map['body'] as String?,
      payload: _decodeJson(map['payload']) ?? const {},
      sourceTable: map['source_table'] as String?,
      sourceId: map['source_id']?.toString(),
      readAt: map['read_at'] == null
          ? null
          : DateTime.parse(map['read_at'] as String).toLocal(),
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
    );
  }

  NotificationItem copyWith({DateTime? readAt}) => NotificationItem(
    id: id,
    profileId: profileId,
    type: type,
    title: title,
    body: body,
    payload: payload,
    sourceTable: sourceTable,
    sourceId: sourceId,
    readAt: readAt ?? this.readAt,
    createdAt: createdAt,
  );

  static Map<String, dynamic>? _decodeJson(dynamic v) {
    if (v == null) return null;
    if (v is Map<String, dynamic>) return v;
    if (v is String && v.isNotEmpty) {
      return jsonDecode(v) as Map<String, dynamic>;
    }
    return null;
  }
}

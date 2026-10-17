double _num(dynamic value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

/// Refund issued for a cancelled order (buyer view only, from
/// `get_order_detail`). Null when nothing was refunded.
class RefundInfo {
  final double amount;

  /// 'wallet' | 'card'
  final String destination;
  final String? cardLast4;
  final String? cardBrand;
  final DateTime? refundedAt;

  const RefundInfo({
    required this.amount,
    required this.destination,
    this.cardLast4,
    this.cardBrand,
    this.refundedAt,
  });

  bool get isCard => destination == 'card';

  static RefundInfo? fromDetailMap(Map<String, dynamic> row) {
    final amount = row['refund_amount'];
    if (amount == null) return null;
    return RefundInfo(
      amount: _num(amount),
      destination: (row['refund_destination'] as String?) ?? 'wallet',
      cardLast4: row['refund_card_last4'] as String?,
      cardBrand: row['refund_card_brand'] as String?,
      refundedAt: DateTime.tryParse((row['refunded_at'] as String?) ?? '')
          ?.toLocal(),
    );
  }
}

/// Result of `get_cancellation_preview`: what cancelling would refund.
class CancellationPreview {
  final bool refundable;
  final double amount;

  /// 'wallet' | 'card' | 'none'
  final String destination;
  final String? cardLast4;
  final String? cardBrand;
  final String? reason;

  const CancellationPreview({
    required this.refundable,
    required this.amount,
    required this.destination,
    this.cardLast4,
    this.cardBrand,
    this.reason,
  });

  factory CancellationPreview.fromMap(Map<String, dynamic> map) {
    return CancellationPreview(
      refundable: map['refundable'] == true,
      amount: _num(map['amount']),
      destination: (map['destination'] as String?) ?? 'none',
      cardLast4: map['card_last4'] as String?,
      cardBrand: map['card_brand'] as String?,
      reason: map['reason'] as String?,
    );
  }
}

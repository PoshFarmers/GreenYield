enum PriceTrendDirection { up, down, stable }

PriceTrendDirection _trendFromDb(String? value) {
  switch (value) {
    case 'up':
      return PriceTrendDirection.up;
    case 'down':
      return PriceTrendDirection.down;
    default:
      return PriceTrendDirection.stable;
  }
}

/// Mirrors the `price_trend` table — one row per crop, the direction
/// and magnitude of its price movement over `periodDays` (7 by default,
/// per `refresh_market_price_analytics()`). Synced read-only via the
/// `price_trends` PowerSync stream.
class PriceTrend {
  final String cropId;
  final PriceTrendDirection direction;
  final double? changePercent;
  final int periodDays;
  final DateTime computedAt;

  const PriceTrend({
    required this.cropId,
    required this.direction,
    this.changePercent,
    required this.periodDays,
    required this.computedAt,
  });

  factory PriceTrend.fromMap(Map<String, dynamic> map) {
    return PriceTrend(
      cropId: map['crop_id'] as String,
      direction: _trendFromDb(map['trend_direction'] as String?),
      changePercent: (map['change_percent'] as num?)?.toDouble(),
      periodDays: (map['period_days'] as num?)?.toInt() ?? 7,
      computedAt:
          DateTime.tryParse(map['computed_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

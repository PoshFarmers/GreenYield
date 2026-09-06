/// Mirrors one row of the `price_history` table — a per-crop, per-day
/// snapshot of average/min/max price from completed orders that day
/// (see `refresh_market_price_analytics()`). Unlike market_price/
/// price_trend, this table has a real `id` primary key in Postgres, so
/// no id-aliasing is needed in its PowerSync stream.
class PriceHistory {
  final String id;
  final String cropId;
  final DateTime priceDate;
  final double avgPricePerKg;
  final double minPricePerKg;
  final double maxPricePerKg;
  final int orderCount;

  const PriceHistory({
    required this.id,
    required this.cropId,
    required this.priceDate,
    required this.avgPricePerKg,
    required this.minPricePerKg,
    required this.maxPricePerKg,
    required this.orderCount,
  });

  factory PriceHistory.fromMap(Map<String, dynamic> map) {
    return PriceHistory(
      id: map['id'] as String,
      cropId: map['crop_id'] as String,
      priceDate:
          DateTime.tryParse(map['price_date'] as String? ?? '') ??
          DateTime.now(),
      avgPricePerKg: (map['avg_price_per_kg'] as num?)?.toDouble() ?? 0,
      minPricePerKg: (map['min_price_per_kg'] as num?)?.toDouble() ?? 0,
      maxPricePerKg: (map['max_price_per_kg'] as num?)?.toDouble() ?? 0,
      orderCount: (map['order_count'] as num?)?.toInt() ?? 0,
    );
  }
}

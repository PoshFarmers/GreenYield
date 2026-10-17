/// Mirrors one row of `price_history`: a per-crop, per-day snapshot built from
/// delivered/completed orders (quantity-weighted average). Rows with
/// [isSynthetic] are seeded starter data, not real orders.
class PriceHistory {
  final String id;
  final String cropId;
  final DateTime priceDate;
  final double avgPricePerKg;
  final double minPricePerKg;
  final double maxPricePerKg;
  final int orderCount;
  final double totalQuantityKg;
  final bool isSynthetic;

  const PriceHistory({
    required this.id,
    required this.cropId,
    required this.priceDate,
    required this.avgPricePerKg,
    required this.minPricePerKg,
    required this.maxPricePerKg,
    required this.orderCount,
    this.totalQuantityKg = 0,
    this.isSynthetic = false,
  });

  factory PriceHistory.fromMap(Map<String, dynamic> map) {
    final synthetic = map['is_synthetic'];
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
      totalQuantityKg: (map['total_quantity_kg'] as num?)?.toDouble() ?? 0,
      isSynthetic: synthetic == 1 || synthetic == true,
    );
  }
}

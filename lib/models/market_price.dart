/// Mirrors the `market_price` table — one row per crop, the latest
/// computed average/min/max price from completed orders (see
/// `refresh_market_price_analytics()` server-side). Synced read-only
/// via the `market_prices` PowerSync stream; clients never write here.
class MarketPrice {
  final String cropId;
  final double? avgPricePerKg;
  final double? minPricePerKg;
  final double? maxPricePerKg;
  final DateTime? asOfDate;
  final DateTime updatedAt;

  const MarketPrice({
    required this.cropId,
    this.avgPricePerKg,
    this.minPricePerKg,
    this.maxPricePerKg,
    this.asOfDate,
    required this.updatedAt,
  });

  factory MarketPrice.fromMap(Map<String, dynamic> map) {
    final asOfDate = map['as_of_date'] as String?;
    return MarketPrice(
      cropId: map['crop_id'] as String,
      avgPricePerKg: (map['avg_price_per_kg'] as num?)?.toDouble(),
      minPricePerKg: (map['min_price_per_kg'] as num?)?.toDouble(),
      maxPricePerKg: (map['max_price_per_kg'] as num?)?.toDouble(),
      asOfDate: asOfDate == null ? null : DateTime.tryParse(asOfDate),
      updatedAt:
          DateTime.tryParse(map['updated_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

/// Mirrors the `market_price` table: one row per crop, a rolling 14-day
/// quantity-weighted average from delivered/completed orders
/// (`refresh_market_price_analytics()`), or the seed baseline when there are
/// too few orders. Synced read-only via the `market_prices` stream.
class MarketPrice {
  final String cropId;
  final double? avgPricePerKg;
  final double? minPricePerKg;
  final double? maxPricePerKg;
  final DateTime? asOfDate;
  final DateTime updatedAt;

  /// Distinct delivered orders behind the figure (0 for seed rows).
  final int sampleSize;

  /// 'orders' | 'seed'
  final String source;

  const MarketPrice({
    required this.cropId,
    this.avgPricePerKg,
    this.minPricePerKg,
    this.maxPricePerKg,
    this.asOfDate,
    required this.updatedAt,
    this.sampleSize = 0,
    this.source = 'seed',
  });

  bool get isEstimated => source != 'orders';

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
      sampleSize: (map['sample_size'] as num?)?.toInt() ?? 0,
      source: (map['source'] as String?) ?? 'seed',
    );
  }
}

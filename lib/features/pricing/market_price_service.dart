import '../../core/local_db/powersync.dart'; // exposes `db`
import '../../models/market_price.dart';
import '../../models/price_history.dart';
import '../../models/price_trend.dart';

/// `market_price` and `price_trend` are keyed by `crop_id` (not a
/// generic local `id`), so single-crop lookups are always by crop id.
class MarketPriceService {
  const MarketPriceService();

  Future<MarketPrice?> getForCrop(String cropId) async {
    final row = await db.getOptional(
      'SELECT * FROM market_price WHERE crop_id = ?',
      [cropId],
    );
    return row == null ? null : MarketPrice.fromMap(row);
  }

  Stream<MarketPrice?> watchForCrop(String cropId) {
    return db
        .watch(
          'SELECT * FROM market_price WHERE crop_id = ?',
          parameters: [cropId],
        )
        .map((rows) => rows.isEmpty ? null : MarketPrice.fromMap(rows.first));
  }

  Future<PriceTrend?> getTrendForCrop(String cropId) async {
    final row = await db.getOptional(
      'SELECT * FROM price_trend WHERE crop_id = ?',
      [cropId],
    );
    return row == null ? null : PriceTrend.fromMap(row);
  }

  Stream<PriceTrend?> watchTrendForCrop(String cropId) {
    return db
        .watch(
          'SELECT * FROM price_trend WHERE crop_id = ?',
          parameters: [cropId],
        )
        .map((rows) => rows.isEmpty ? null : PriceTrend.fromMap(rows.first));
  }

  /// Every market_price row for a given set of crop ids, keyed by
  /// crop_id — used by the farmer home screen to show all of a
  /// farmer's tracked crops in one query rather than one stream per
  /// crop. Returns an empty map for an empty [cropIds] list rather
  /// than issuing a query with no IN clause.
  Stream<Map<String, MarketPrice>> watchForCrops(List<String> cropIds) {
    if (cropIds.isEmpty) return Stream.value(const {});
    final placeholders = List.filled(cropIds.length, '?').join(', ');
    return db
        .watch(
          'SELECT * FROM market_price WHERE crop_id IN ($placeholders)',
          parameters: cropIds,
        )
        .map((rows) {
          final map = <String, MarketPrice>{};
          for (final row in rows) {
            final price = MarketPrice.fromMap(row);
            map[price.cropId] = price;
          }
          return map;
        });
  }

  /// Same idea as [watchForCrops], for trends.
  Stream<Map<String, PriceTrend>> watchTrendsForCrops(List<String> cropIds) {
    if (cropIds.isEmpty) return Stream.value(const {});
    final placeholders = List.filled(cropIds.length, '?').join(', ');
    return db
        .watch(
          'SELECT * FROM price_trend WHERE crop_id IN ($placeholders)',
          parameters: cropIds,
        )
        .map((rows) {
          final map = <String, PriceTrend>{};
          for (final row in rows) {
            final trend = PriceTrend.fromMap(row);
            map[trend.cropId] = trend;
          }
          return map;
        });
  }

  Future<List<PriceHistory>> getRecentHistory(
    String cropId, {
    int limit = 30,
  }) async {
    final rows = await db.getAll(
      'SELECT * FROM price_history WHERE crop_id = ? '
      'ORDER BY price_date DESC LIMIT ?',
      [cropId, limit],
    );
    return rows.map(PriceHistory.fromMap).toList();
  }
}

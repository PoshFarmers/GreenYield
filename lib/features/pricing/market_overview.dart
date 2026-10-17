import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/local_db/powersync.dart'; // exposes `db`
import '../../models/market_price.dart';

/// One crop with its market price and 7-day trend (all from the local mirror).
class MarketOverviewRow {
  final String cropId;
  final String name;
  final String category;
  final String? fallbackImageUrl;
  final double? avg;
  final double? min;
  final double? max;
  final int sampleSize;
  final String source;
  final String? trendDirection;
  final double? changePercent;

  const MarketOverviewRow({
    required this.cropId,
    required this.name,
    required this.category,
    this.fallbackImageUrl,
    this.avg,
    this.min,
    this.max,
    this.sampleSize = 0,
    this.source = 'seed',
    this.trendDirection,
    this.changePercent,
  });

  factory MarketOverviewRow.fromMap(Map<String, dynamic> m) =>
      MarketOverviewRow(
        cropId: m['crop_id'] as String,
        name: m['name'] as String,
        category: (m['category'] as String?) ?? 'vegetable',
        fallbackImageUrl: m['fallback_image_url'] as String?,
        avg: (m['avg_price_per_kg'] as num?)?.toDouble(),
        min: (m['min_price_per_kg'] as num?)?.toDouble(),
        max: (m['max_price_per_kg'] as num?)?.toDouble(),
        sampleSize: (m['sample_size'] as num?)?.toInt() ?? 0,
        source: (m['source'] as String?) ?? 'seed',
        trendDirection: m['trend_direction'] as String?,
        changePercent: (m['change_percent'] as num?)?.toDouble(),
      );
}

class MarketOverviewService {
  const MarketOverviewService();

  Stream<List<MarketOverviewRow>> watchOverview() {
    return db
        .watch('''
          SELECT c.id AS crop_id, c.name, c.category, c.fallback_image_url,
                 mp.avg_price_per_kg, mp.min_price_per_kg, mp.max_price_per_kg,
                 mp.sample_size, mp.source,
                 pt.trend_direction, pt.change_percent
          FROM crop c
          LEFT JOIN market_price mp ON mp.crop_id = c.id
          LEFT JOIN price_trend pt ON pt.crop_id = c.id
          ORDER BY c.name
          ''')
        .map((rows) => rows.map(MarketOverviewRow.fromMap).toList());
  }

  /// Daily average prices for the last [days] days, oldest first, per crop.
  Stream<Map<String, List<double>>> watchSparklines({int days = 30}) {
    final from = DateTime.now().subtract(Duration(days: days - 1));
    final f =
        '${from.year.toString().padLeft(4, '0')}-'
        '${from.month.toString().padLeft(2, '0')}-'
        '${from.day.toString().padLeft(2, '0')}';
    return db
        .watch(
          'SELECT crop_id, avg_price_per_kg FROM price_history '
          'WHERE price_date >= ? ORDER BY price_date ASC',
          parameters: [f],
        )
        .map((rows) {
          final out = <String, List<double>>{};
          for (final r in rows) {
            final v = (r['avg_price_per_kg'] as num?)?.toDouble();
            if (v == null) continue;
            out.putIfAbsent(r['crop_id'] as String, () => []).add(v);
          }
          return out;
        });
  }
}

/// Market price per crop id, for chips on produce cards / listing detail.
final marketAveragesProvider = StreamProvider<Map<String, MarketPrice>>(
  (ref) => db.watch('SELECT * FROM market_price').map((rows) {
    final map = <String, MarketPrice>{};
    for (final row in rows) {
      final price = MarketPrice.fromMap(row);
      map[price.cropId] = price;
    }
    return map;
  }),
);

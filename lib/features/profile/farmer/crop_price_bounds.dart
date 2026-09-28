import 'dart:async';

import '../../../core/local_db/powersync.dart'; // exposes `db`

/// Fallback min/max price-per-kg bounds by crop name. The source of truth is
/// now `crop.price_floor_per_kg` / `price_ceiling_per_kg` (synced); this map is
/// used until that row has synced, or for crops without bounds. The server
/// clamps listing/default prices into the bounds (see the Task 12 migration).
const Map<String, ({double min, double max})> cropPriceBounds = {
  'Tomato': (min: 150, max: 250),
  'Carrot': (min: 120, max: 200),
  'Cabbage': (min: 80, max: 150),
  'Eggplant': (min: 100, max: 180),
  'Brinjal': (min: 100, max: 180), // legacy alias
  'Okra': (min: 150, max: 220),
  'Pumpkin': (min: 60, max: 120),
  'Cucumber': (min: 80, max: 150),
  'Green Beans': (min: 200, max: 300),
  'Potato': (min: 180, max: 280),
  'Onion': (min: 200, max: 320),
  'Beetroot': (min: 150, max: 220),
  'Red bell pepper': (min: 250, max: 400),
  'Capsicum': (min: 250, max: 400), // legacy alias
  'Banana': (min: 100, max: 180),
  'Mango': (min: 150, max: 350),
  'Papaya': (min: 80, max: 150),
  'Pineapple': (min: 100, max: 200),
  'Watermelon': (min: 60, max: 120),
  'Orange': (min: 150, max: 280),
  'Guava': (min: 120, max: 200),
  'Jackfruit': (min: 80, max: 150),
  'Rambutan': (min: 200, max: 350),
  'Mangosteen': (min: 400, max: 700),
};

const ({double min, double max}) _defaultPriceBounds = (min: 100, max: 300);

final Map<String, ({double min, double max})> _serverBounds = {};
StreamSubscription<dynamic>? _boundsSub;

/// Starts (once) a watch on the synced crop bounds. Kept lazy and guarded so
/// calling `priceBoundsFor` before the local DB is ready just uses the map.
void _watchServerBounds() {
  if (_boundsSub != null) return;
  try {
    _boundsSub = db
        .watch(
          'SELECT name, price_floor_per_kg AS lo, price_ceiling_per_kg AS hi '
          'FROM crop WHERE price_floor_per_kg IS NOT NULL '
          'AND price_ceiling_per_kg IS NOT NULL',
        )
        .listen((rows) {
          _serverBounds
            ..clear()
            ..addEntries([
              for (final r in rows)
                MapEntry(r['name'] as String, (
                  min: (r['lo'] as num).toDouble(),
                  max: (r['hi'] as num).toDouble(),
                )),
            ]);
        }, onError: (_) {});
  } catch (_) {
    _boundsSub = null; // db not ready yet: retry on the next call
  }
}

/// Synced server bounds, else the hardcoded map, else 100-300. The first call
/// before the crops stream emits returns the map values; later calls (and
/// rebuilds) use the server's.
({double min, double max}) priceBoundsFor(String cropName) {
  _watchServerBounds();
  return _serverBounds[cropName] ??
      cropPriceBounds[cropName] ??
      _defaultPriceBounds;
}

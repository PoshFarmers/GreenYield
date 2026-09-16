import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/marketplace_listing.dart';

/// Local fallback for the marketplace search feed. The marketplace is
/// deliberately server-only (see MarketplaceService's doc comment) —
/// this doesn't make it offline-*first*, it just means the last
/// successful search stays browsable instead of the screen going
/// completely blank the moment connectivity drops.
class MarketplaceCache {
  static const _prefix = 'marketplace_cache_v1_';
  static const _maxAge = Duration(hours: 24);

  Future<void> save(String key, List<MarketplaceListing> listings) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = jsonEncode({
      'saved_at': DateTime.now().toIso8601String(),
      'listings': listings.map((l) => l.toMap()).toList(),
    });
    await prefs.setString('$_prefix$key', payload);
  }

  Future<List<MarketplaceListing>?> load(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefix$key');
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final savedAt = DateTime.tryParse(decoded['saved_at'] as String? ?? '');
      if (savedAt == null || DateTime.now().difference(savedAt) > _maxAge) {
        return null;
      }
      return (decoded['listings'] as List)
          .map((m) => MarketplaceListing.fromMap(m as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return null;
    }
  }

  String keyFor({String? query, String? category, String? farmerId}) =>
      '${query ?? ''}|${category ?? ''}|${farmerId ?? ''}';
}

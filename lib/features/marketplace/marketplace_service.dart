import '../../core/supabase/client.dart';
import '../../models/marketplace_listing.dart';
import '../../models/profile.dart';

/// The marketplace is the one feature that talks to Supabase directly
/// instead of reading the PowerSync mirror.
///
/// Why: buyers can't read `profile`/`farmer_crop` under RLS (own-row
/// only), and distance sorting + typo-tolerant search need PostGIS and
/// pg_trgm, neither of which exists in local SQLite. The RPCs are
/// SECURITY DEFINER and return only marketplace-safe farmer fields.
///
/// Consequence: this feature requires a connection. Everything else in
/// the app stays offline-first.
class MarketplaceService {
  const MarketplaceService();

  Future<List<MarketplaceListing>> search({
    String? query,
    String? category,
    String? farmerId,
    GeoPoint? buyerLocation,
    int limit = 20,
    int offset = 0,
  }) async {
    final rows = await supabase.rpc(
      'search_marketplace_listings',
      params: {
        'p_query': (query == null || query.trim().isEmpty)
            ? null
            : query.trim(),
        'p_category': category,
        'p_farmer_id': farmerId,
        'p_buyer_lat': buyerLocation?.latitude,
        'p_buyer_lng': buyerLocation?.longitude,
        'p_limit': limit,
        'p_offset': offset,
      },
    );

    return (rows as List)
        .map((row) => MarketplaceListing.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// Returns null if the listing no longer exists.
  Future<MarketplaceListing?> getListing(
    String listingId, {
    GeoPoint? buyerLocation,
  }) async {
    final rows = await supabase.rpc(
      'get_marketplace_listing',
      params: {
        'p_listing_id': listingId,
        'p_buyer_lat': buyerLocation?.latitude,
        'p_buyer_lng': buyerLocation?.longitude,
      },
    );

    final list = rows as List;
    if (list.isEmpty) return null;
    return MarketplaceListing.fromMap(list.first as Map<String, dynamic>);
  }

  Future<List<MarketplaceFarmer>> farmers({
    GeoPoint? buyerLocation,
    int limit = 10,
  }) async {
    final rows = await supabase.rpc(
      'list_marketplace_farmers',
      params: {
        'p_buyer_lat': buyerLocation?.latitude,
        'p_buyer_lng': buyerLocation?.longitude,
        'p_limit': limit,
      },
    );

    return (rows as List)
        .map((row) => MarketplaceFarmer.fromMap(row as Map<String, dynamic>))
        .toList();
  }
}

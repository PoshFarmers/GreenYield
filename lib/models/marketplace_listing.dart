/// One row from `search_marketplace_listings` / `get_marketplace_listing`.
///
/// Unlike the rest of the app's models this is NOT backed by a PowerSync
/// table — the marketplace is server-queried, because buyers can't read
/// farmer profiles under RLS and distance/typo-tolerant search need
/// PostGIS + pg_trgm. See the migration header for the reasoning.
///
/// Farmer fields are the marketplace-safe subset the RPC exposes; there
/// is deliberately no phone or address here.
class MarketplaceListing {
  final String id;
  final String farmerProfileId;
  final String farmerName;
  final String? farmerAvatarUrl;
  final String? farmerLocationText;
  final String cropId;
  final String cropName;
  final String cropCategory; // 'vegetable' | 'fruit'

  /// Already resolved server-side through
  /// listing -> farmer_crop -> crop.fallback_image_url.
  final String? imageUrl;
  final String? description;

  final double pricePerKg;
  final double availableQuantityKg;
  final DateTime? harvestedOn;
  final DateTime? publishedAt;

  /// Null when the buyer has no saved location, or the farmer has none.
  final double? distanceKm;

  const MarketplaceListing({
    required this.id,
    required this.farmerProfileId,
    required this.farmerName,
    required this.cropId,
    required this.cropName,
    required this.cropCategory,
    required this.pricePerKg,
    required this.availableQuantityKg,
    this.farmerAvatarUrl,
    this.farmerLocationText,
    this.imageUrl,
    this.description,
    this.harvestedOn,
    this.publishedAt,
    this.distanceKm,
  });

  bool get isSoldOut => availableQuantityKg <= 0;

  factory MarketplaceListing.fromMap(Map<String, dynamic> map) {
    return MarketplaceListing(
      id: map['id'] as String,
      farmerProfileId: map['farmer_profile_id'] as String,
      farmerName: (map['farmer_name'] as String?) ?? '',
      farmerAvatarUrl: map['farmer_avatar_url'] as String?,
      farmerLocationText: map['farmer_location_text'] as String?,
      cropId: map['crop_id'] as String,
      cropName: (map['crop_name'] as String?) ?? '',
      cropCategory: (map['crop_category'] as String?) ?? 'vegetable',
      imageUrl: map['image_url'] as String?,
      description: map['description'] as String?,
      // PostgREST sends numeric as either num or String depending on size.
      pricePerKg: _toDouble(map['price_per_kg']) ?? 0,
      availableQuantityKg: _toDouble(map['available_quantity_kg']) ?? 0,
      harvestedOn: _toDate(map['harvested_on']),
      publishedAt: _toDate(map['published_at']),
      distanceKm: _toDouble(map['distance_km']),
    );
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static DateTime? _toDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }
}

/// A farmer with at least one active listing — the discovery row shown
/// when the buyer isn't searching. From `list_marketplace_farmers`.
class MarketplaceFarmer {
  final String farmerProfileId;
  final String farmerName;
  final String? farmerAvatarUrl;
  final String? farmerLocationText;
  final List<String> cropNames;
  final int listingCount;
  final double? distanceKm;

  const MarketplaceFarmer({
    required this.farmerProfileId,
    required this.farmerName,
    required this.cropNames,
    required this.listingCount,
    this.farmerAvatarUrl,
    this.farmerLocationText,
    this.distanceKm,
  });

  factory MarketplaceFarmer.fromMap(Map<String, dynamic> map) {
    return MarketplaceFarmer(
      farmerProfileId: map['farmer_profile_id'] as String,
      farmerName: (map['farmer_name'] as String?) ?? '',
      farmerAvatarUrl: map['farmer_avatar_url'] as String?,
      farmerLocationText: map['farmer_location_text'] as String?,
      cropNames: ((map['crop_names'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      listingCount: (map['listing_count'] as num?)?.toInt() ?? 0,
      distanceKm: MarketplaceListing._toDouble(map['distance_km']),
    );
  }
}

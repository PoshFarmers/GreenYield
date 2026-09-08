/// A farmer as any buyer can see them — from the `get_farmer_public_profile`
/// RPC. Not backed by a PowerSync table: `profile`/`farmer_crop` only sync
/// the signed-in user's own rows (RLS), so cross-user reads go through a
/// SECURITY DEFINER RPC instead, same reasoning as `MarketplaceListing`.
class FarmerPublicProfile {
  final String farmerProfileId;
  final String farmerName;
  final String? farmerAvatarUrl;
  final String? farmerLocationText;
  final double avgRating;
  final int reviewCount;
  final List<FarmerPublicCrop> crops;
  final List<FarmerPublicReview> reviews;

  const FarmerPublicProfile({
    required this.farmerProfileId,
    required this.farmerName,
    this.farmerAvatarUrl,
    this.farmerLocationText,
    required this.avgRating,
    required this.reviewCount,
    required this.crops,
    required this.reviews,
  });

  factory FarmerPublicProfile.fromMap(Map<String, dynamic> map) {
    return FarmerPublicProfile(
      farmerProfileId: map['farmer_profile_id'] as String,
      farmerName: (map['farmer_name'] as String?)?.trim().isNotEmpty == true
          ? (map['farmer_name'] as String).trim()
          : 'Farmer',
      farmerAvatarUrl: map['farmer_avatar_url'] as String?,
      farmerLocationText: map['farmer_location_text'] as String?,
      avgRating: (map['avg_rating'] as num?)?.toDouble() ?? 0,
      reviewCount: (map['review_count'] as num?)?.toInt() ?? 0,
      crops: ((map['crops'] as List?) ?? const [])
          .map((e) => FarmerPublicCrop.fromMap(e as Map<String, dynamic>))
          .toList(),
      reviews: ((map['reviews'] as List?) ?? const [])
          .map((e) => FarmerPublicReview.fromMap(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// One crop on the farmer's menu, with the total stock currently for
/// sale across their active listings of it (0 when nothing's listed).
class FarmerPublicCrop {
  final String cropId;
  final String cropName;
  final String cropCategory;
  final String? description;
  final double? defaultPricePerKg;
  final String? farmerCropImageUrl;
  final String? cropFallbackImageUrl;
  final double availableQuantityKg;

  const FarmerPublicCrop({
    required this.cropId,
    required this.cropName,
    required this.cropCategory,
    this.description,
    this.defaultPricePerKg,
    this.farmerCropImageUrl,
    this.cropFallbackImageUrl,
    required this.availableQuantityKg,
  });

  /// Mirrors `FarmerCrop.displayImage` / `MarketplaceListing.displayImage`
  /// — the farmer's own crop photo when set, else the catalogue fallback.
  ({String? path, String bucket, bool isFallback}) get displayImage {
    if (farmerCropImageUrl != null) {
      return (
        path: farmerCropImageUrl,
        bucket: 'crop-photos',
        isFallback: false,
      );
    }
    return (
      path: cropFallbackImageUrl,
      bucket: 'crop-fallback-images',
      isFallback: true,
    );
  }

  factory FarmerPublicCrop.fromMap(Map<String, dynamic> map) {
    return FarmerPublicCrop(
      cropId: map['crop_id'] as String,
      cropName: (map['crop_name'] as String?) ?? '',
      cropCategory: (map['crop_category'] as String?) ?? 'vegetable',
      description: map['description'] as String?,
      defaultPricePerKg: (map['default_price_per_kg'] as num?)?.toDouble(),
      farmerCropImageUrl: map['farmer_crop_image_url'] as String?,
      cropFallbackImageUrl: map['crop_fallback_image_url'] as String?,
      availableQuantityKg:
          (map['available_quantity_kg'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// One review as shown on the farmer's public profile — the buyer's
/// name, not their id (this is a read-only display row, not something
/// the viewer can act on unless it's their own).
class FarmerPublicReview {
  final String id;
  final int rating;
  final String? comment;
  final DateTime createdAt;
  final String buyerName;

  const FarmerPublicReview({
    required this.id,
    required this.rating,
    this.comment,
    required this.createdAt,
    required this.buyerName,
  });

  factory FarmerPublicReview.fromMap(Map<String, dynamic> map) {
    return FarmerPublicReview(
      id: map['id'] as String,
      rating: (map['rating'] as num?)?.toInt() ?? 0,
      comment: map['comment'] as String?,
      createdAt:
          DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
      buyerName: (map['buyer_name'] as String?)?.trim().isNotEmpty == true
          ? (map['buyer_name'] as String).trim()
          : 'Buyer',
    );
  }
}

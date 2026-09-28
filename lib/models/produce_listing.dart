/// A farmer's live "for sale right now" row, joined with its crop and
/// with the farmer_crop fallbacks already resolved — see
/// `context folder/CROP_AND_LISTING_DESIGN.md` for how listings differ
/// from farmer_crop (inventory vs. menu).
class ProduceListing {
  final String id;
  final String cropId;
  final String cropName;
  final String category;
  final double pricePerKg;
  final double availableQuantityKg;

  /// 'active' | 'sold_out' | 'expired' | 'flagged'
  final String status;

  /// Already coalesced: listing's own value, else the farmer_crop one.
  final String? description;

  /// The un-coalesced parts of [description]: this batch's own override
  /// (null = inheriting) and the farmer_crop default it falls back to.
  /// The edit screen needs them apart, so clearing the override restores
  /// the fallback instead of copying the crop text into the listing.
  final String? listingDescription;
  final String? cropDescription;

  /// The three tiers of the image fallback chain, kept separate (rather
  /// than pre-coalesced into one path) because each tier lives in a
  /// different bucket -- see [displayImage].
  final String? listingImageUrl;
  final String? farmerCropImageUrl;
  final String? cropFallbackImageUrl;

  final DateTime? harvestedOn;
  final DateTime? publishedAt;

  /// Only active / sold-out batches can have their stock changed; expired
  /// and flagged ones are read-only (mirrors adjust_own_listing_stock).
  bool get isStockEditable => status == 'active' || status == 'sold_out';

  const ProduceListing({
    required this.id,
    required this.cropId,
    required this.cropName,
    required this.category,
    required this.pricePerKg,
    required this.availableQuantityKg,
    required this.status,
    this.description,
    this.listingDescription,
    this.cropDescription,
    this.listingImageUrl,
    this.farmerCropImageUrl,
    this.cropFallbackImageUrl,
    this.harvestedOn,
    this.publishedAt,
  });

  double get totalValue => pricePerKg * availableQuantityKg;

  /// Path + bucket to actually display: the listing's own photo, else
  /// the farmer's standing crop photo, else the crop catalogue's
  /// fallback image. Mirrors `FarmerCrop.displayImage` and the same
  /// chain `search_marketplace_listings` resolves server-side.
  ({String? path, String bucket, bool isFallback}) get displayImage {
    if (listingImageUrl != null) {
      return (path: listingImageUrl, bucket: 'crop-photos', isFallback: false);
    }
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

  factory ProduceListing.fromMap(Map<String, dynamic> map) {
    final harvestedOn = map['harvested_on'] as String?;
    return ProduceListing(
      id: map['id'] as String,
      cropId: map['crop_id'] as String,
      cropName: map['crop_name'] as String,
      category: map['crop_category'] as String? ?? 'vegetable',
      pricePerKg: (map['price_per_kg'] as num?)?.toDouble() ?? 0,
      availableQuantityKg:
          (map['available_quantity_kg'] as num?)?.toDouble() ?? 0,
      status: map['status_text'] as String? ?? 'active',
      description: map['description'] as String?,
      listingDescription: map['listing_description'] as String?,
      cropDescription: map['crop_description'] as String?,
      listingImageUrl: map['listing_image_url'] as String?,
      farmerCropImageUrl: map['farmer_crop_image_url'] as String?,
      cropFallbackImageUrl: map['crop_fallback_image_url'] as String?,
      harvestedOn: harvestedOn == null ? null : DateTime.tryParse(harvestedOn),
      publishedAt: DateTime.tryParse(map['published_at'] as String? ?? ''),
    );
  }
}

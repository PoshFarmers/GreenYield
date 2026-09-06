class Crop {
  final String id;
  final String name;
  final String category; // 'vegetable' | 'fruit'
  final String? fallbackImageUrl;

  const Crop({
    required this.id,
    required this.name,
    required this.category,
    this.fallbackImageUrl,
  });

  factory Crop.fromMap(Map<String, dynamic> map) {
    return Crop(
      id: map['id'] as String,
      name: map['name'] as String,
      category: map['category'] as String,
      fallbackImageUrl: map['fallback_image_url'] as String?,
    );
  }
}

/// A crop as registered on a specific farmer's menu — the catalogue
/// crop joined with this farmer's own description/price/photo for it
/// (farmer_crop columns).
class FarmerCrop {
  final String cropId;
  final String cropName;
  final String category;
  final String? description;
  final double? defaultPricePerKg;
  final String? imageUrl;
  final String? fallbackImageUrl;

  const FarmerCrop({
    required this.cropId,
    required this.cropName,
    required this.category,
    this.description,
    this.defaultPricePerKg,
    this.imageUrl,
    this.fallbackImageUrl,
  });

  /// Path + bucket to actually display: the farmer's own photo when set,
  /// otherwise the crop catalogue's fallback image. Mirrors the
  /// `coalesce(fc.image_url, c.fallback_image_url)` chain used
  /// server-side by the `farmer_crop_read` view.
  ({String? path, String bucket, bool isFallback}) get displayImage {
    if (imageUrl != null) {
      return (path: imageUrl, bucket: 'crop-photos', isFallback: false);
    }
    return (
      path: fallbackImageUrl,
      bucket: 'crop-fallback-images',
      isFallback: true,
    );
  }

  factory FarmerCrop.fromMap(Map<String, dynamic> map) {
    return FarmerCrop(
      cropId: map['id'] as String,
      cropName: map['name'] as String,
      category: map['category'] as String,
      description: map['description'] as String?,
      defaultPricePerKg: (map['default_price_per_kg'] as num?)?.toDouble(),
      imageUrl: map['image_url'] as String?,
      fallbackImageUrl: map['fallback_image_url'] as String?,
    );
  }
}

/// One crop entry to write to `farmer_crop` — used both at onboarding
/// (createProfile) and when editing a single crop later (upsertCrop).
class FarmerCropInput {
  final String cropId;
  final String? description;
  final double? defaultPricePerKg;
  final String? imageUrl;

  const FarmerCropInput({
    required this.cropId,
    this.description,
    this.defaultPricePerKg,
    this.imageUrl,
  });
}

class FarmerProfile {
  final String profileId;
  final List<FarmerCrop> crops;

  const FarmerProfile({required this.profileId, this.crops = const []});
}

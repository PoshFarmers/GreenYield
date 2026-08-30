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
  final String? imageUrl;

  final DateTime? harvestedOn;

  const ProduceListing({
    required this.id,
    required this.cropId,
    required this.cropName,
    required this.category,
    required this.pricePerKg,
    required this.availableQuantityKg,
    required this.status,
    this.description,
    this.imageUrl,
    this.harvestedOn,
  });

  double get totalValue => pricePerKg * availableQuantityKg;

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
      imageUrl: map['image_url'] as String?,
      harvestedOn: harvestedOn == null ? null : DateTime.tryParse(harvestedOn),
    );
  }
}

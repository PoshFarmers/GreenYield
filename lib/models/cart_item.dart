/// One row of the buyer's cart, joined against the local `produce_listing`
/// and `crop` mirrors so the cart screen can render price/name/stock
/// entirely offline — no marketplace RPC needed just to show what's in
/// the cart.
///
/// `farmer_profile_id` travels with the row (it's a column on
/// `produce_listing`) so the UI can group items by farmer for the
/// per-farmer subtotal without any extra join. The farmer's *display
/// name* is not available locally (buyers only sync their own `profile`
/// row under RLS) — callers that want a friendly name enrich this with
/// `MarketplaceService.getListing` per unique `produceListingId`, same
/// as the listing detail screen already does.
class CartLineItem {
  final String cartItemId;
  final String produceListingId;
  final String farmerProfileId;
  final String cropId;
  final String cropName;
  final String category;

  /// Snapshot is NOT taken here — this always reflects the *current*
  /// listing price/stock, since the cart hasn't checked out yet and
  /// farmers may edit a listing while it sits in someone's cart.
  final double pricePerKg;
  final double availableQuantityKg;

  /// 'active' | 'sold_out' | 'expired' | 'flagged'
  final String listingStatus;

  final String? imageUrl;
  final double quantityKg;
  final DateTime? addedAt;

  const CartLineItem({
    required this.cartItemId,
    required this.produceListingId,
    required this.farmerProfileId,
    required this.cropId,
    required this.cropName,
    required this.category,
    required this.pricePerKg,
    required this.availableQuantityKg,
    required this.listingStatus,
    required this.quantityKg,
    this.imageUrl,
    this.addedAt,
  });

  double get lineTotal => pricePerKg * quantityKg;

  /// A listing can go stale while sitting in the cart — sold out,
  /// unpublished by the farmer, or the buyer's saved quantity now
  /// exceeds what's left. The cart screen flags these rather than
  /// silently letting checkout fail later.
  bool get isUnavailable =>
      listingStatus != 'active' || availableQuantityKg <= 0;

  bool get exceedsStock => quantityKg > availableQuantityKg;

  factory CartLineItem.fromMap(Map<String, dynamic> map) {
    final addedAt = map['created_at'] as String?;
    return CartLineItem(
      cartItemId: map['id'] as String,
      produceListingId: map['produce_listing_id'] as String,
      farmerProfileId: map['farmer_profile_id'] as String,
      cropId: map['crop_id'] as String,
      cropName: (map['crop_name'] as String?) ?? '',
      category: (map['crop_category'] as String?) ?? 'vegetable',
      pricePerKg: _toDouble(map['price_per_kg']) ?? 0,
      availableQuantityKg: _toDouble(map['available_quantity_kg']) ?? 0,
      listingStatus: (map['status_text'] as String?) ?? 'active',
      imageUrl: map['image_url'] as String?,
      quantityKg: _toDouble(map['quantity_kg']) ?? 0,
      addedAt: addedAt == null ? null : DateTime.tryParse(addedAt),
    );
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}

/// All of one farmer's [CartLineItem]s plus their subtotal — the unit
/// the cart screen actually renders (per-farmer grouping, since
/// checkout will split into one order per farmer).
class CartFarmerGroup {
  final String farmerProfileId;
  final List<CartLineItem> items;

  const CartFarmerGroup({required this.farmerProfileId, required this.items});

  double get subtotal => items.fold(0, (sum, item) => sum + item.lineTotal);

  bool get hasUnavailableItems => items.any((item) => item.isUnavailable);
}

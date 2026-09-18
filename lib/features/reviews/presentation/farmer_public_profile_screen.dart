import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/app_secondary_header.dart';
import '../../../core/widgets/avatar_image.dart';
import '../../../core/widgets/media_image.dart';
import '../../../models/farmer_public_profile.dart';
import '../../../models/farmer_review.dart';
import '../../../models/marketplace_listing.dart';
import '../../../models/profile.dart';
import '../../marketplace/presentation/listing_detail_screen.dart';
import '../farmer_public_profile_service.dart';
import '../farmer_review_service.dart';
import 'widgets/review_dialog.dart';
import 'widgets/review_tile.dart';
import 'widgets/star_rating.dart';

/// A farmer's public-facing profile — reached by tapping the farmer card
/// on a listing. Shows rating/reviews, location, crops grown, and how
/// much of each is currently available, plus (only for a buyer who has
/// an unreviewed delivered order with this farmer) a way to rate/review.
class FarmerPublicProfileScreen extends StatefulWidget {
  final String farmerProfileId;
  final Profile buyerProfile;

  /// Shown immediately while the full profile loads.
  final String? initialFarmerName;
  final String? initialFarmerAvatarUrl;

  /// When set (opened from the marketplace's Farmers tab), shows a
  /// "Shop all produce" button that hands back to the marketplace's
  /// farmer-filtered grid. Left null where that grid isn't reachable,
  /// e.g. when opened from a listing's farmer card.
  final VoidCallback? onShopAll;

  const FarmerPublicProfileScreen({
    super.key,
    required this.farmerProfileId,
    required this.buyerProfile,
    this.initialFarmerName,
    this.initialFarmerAvatarUrl,
    this.onShopAll,
  });

  @override
  State<FarmerPublicProfileScreen> createState() =>
      _FarmerPublicProfileScreenState();
}

class _FarmerPublicProfileScreenState extends State<FarmerPublicProfileScreen> {
  final _service = const FarmerPublicProfileService();
  late Future<FarmerPublicProfile?> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.fetchProfile(widget.farmerProfileId);
  }

  void _reload() {
    setState(() => _future = _service.fetchProfile(widget.farmerProfileId));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppSecondaryHeader(
        title: widget.initialFarmerName ?? 'Farmer Profile',
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: FutureBuilder<FarmerPublicProfile?>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _buildError(context, snapshot.error.toString());
                }
                final profile = snapshot.data;
                if (profile == null) {
                  return _buildError(
                    context,
                    'This farmer profile is unavailable.',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    _reload();
                    await _future;
                  },
                  child: _buildContent(context, profile),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context, String message) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, FarmerPublicProfile profile) {
    final theme = Theme.of(context);
    // In-stock crops first, so what a buyer can actually order is on top;
    // the RPC's alphabetical order is kept within each group.
    final crops = [
      ...profile.crops.where((c) => c.availableQuantityKg > 0),
      ...profile.crops.where((c) => c.availableQuantityKg <= 0),
    ];
    final inStockCount = profile.crops
        .where((c) => c.availableQuantityKg > 0)
        .length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _buildHeaderCard(theme, profile),
        if (widget.onShopAll != null && inStockCount > 0) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                widget.onShopAll!();
              },
              icon: const Icon(Icons.storefront_outlined),
              label: const Text('Shop all produce'),
            ),
          ),
        ],
        const SizedBox(height: 16),
        _ReviewCallToAction(
          buyerProfileId: widget.buyerProfile.id,
          farmerProfileId: profile.farmerProfileId,
          farmerName: profile.farmerName,
          onSubmitted: _reload,
        ),
        const SizedBox(height: 24),
        _buildSectionHeader(theme, 'Produce'),
        if (profile.crops.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            inStockCount == 0
                ? 'Nothing in stock right now'
                : '$inStockCount of ${profile.crops.length} in stock · tap to see batches',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (crops.isEmpty)
          const _EmptyState(
            icon: Icons.eco_outlined,
            message: "This farmer hasn't added any crops yet.",
          )
        else
          ...crops.map(
            (crop) => _CropTile(
              crop: crop,
              farmer: profile,
              buyerProfile: widget.buyerProfile,
            ),
          ),
        const SizedBox(height: 24),
        _buildSectionHeader(theme, 'Reviews (${profile.reviewCount})'),
        const SizedBox(height: 12),
        if (profile.reviews.isEmpty)
          const _EmptyState(
            icon: Icons.rate_review_outlined,
            message: 'No reviews yet — be the first to share your experience.',
          )
        else
          ...profile.reviews.map(
            (review) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ReviewTile(
                buyerName: review.buyerName,
                rating: review.rating,
                comment: review.comment,
                createdAt: review.createdAt,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildHeaderCard(ThemeData theme, FarmerPublicProfile profile) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AvatarImage(
                path: profile.farmerAvatarUrl ?? widget.initialFarmerAvatarUrl,
                radius: 32,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.farmerName,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (profile.farmerLocationText != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.place_outlined,
                            size: 15,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              profile.farmerLocationText!,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        StarRatingDisplay(rating: profile.avgRating, size: 16),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            profile.reviewCount == 0
                                ? 'No reviews yet'
                                : '${profile.avgRating.toStringAsFixed(1)} (${profile.reviewCount} ${profile.reviewCount == 1 ? 'review' : 'reviews'})',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title) {
    return Text(
      title,
      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
    );
  }
}

/// Shows "Rate & review" (no review yet) or "Edit your review" (already
/// reviewed) — only once the buyer actually has a delivered order with
/// this farmer. Hidden entirely otherwise (no order, or still in
/// progress), per the "only buyers who purchased and completed an
/// order" rule.
class _ReviewCallToAction extends StatelessWidget {
  final String buyerProfileId;
  final String farmerProfileId;
  final String farmerName;
  final VoidCallback onSubmitted;

  const _ReviewCallToAction({
    required this.buyerProfileId,
    required this.farmerProfileId,
    required this.farmerName,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final service = const FarmerReviewService();
    return StreamBuilder<String?>(
      stream: service.watchLatestDeliveredOrderId(
        buyerProfileId: buyerProfileId,
        farmerProfileId: farmerProfileId,
      ),
      builder: (context, orderSnapshot) {
        final orderId = orderSnapshot.data;
        if (orderId == null) return const SizedBox.shrink();

        return StreamBuilder<FarmerReview?>(
          stream: service.watchReviewForOrder(orderId),
          builder: (context, reviewSnapshot) {
            final existingReview = reviewSnapshot.data;
            final isEditing = existingReview != null;

            return SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final result = await ReviewDialog.show(
                    context,
                    orderId: orderId,
                    farmerName: farmerName,
                    existingReview: existingReview,
                  );
                  if (result == true) {
                    onSubmitted();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Thanks for your review!'),
                        ),
                      );
                    }
                  }
                },
                icon: Icon(
                  isEditing ? Icons.edit_outlined : Icons.star_outline,
                ),
                label: Text(isEditing ? 'Edit your review' : 'Rate & review'),
              ),
            );
          },
        );
      },
    );
  }
}

/// Opens [ListingDetailScreen] for one batch, pre-filled with a
/// [MarketplaceListing] assembled from what the profile already has, so
/// the detail screen paints immediately instead of showing a spinner
/// while it fetches the fresh copy.
void _openListing(
  BuildContext context, {
  required FarmerPublicProfile farmer,
  required FarmerPublicCrop crop,
  required FarmerCropListing listing,
  required Profile buyerProfile,
}) {
  final initial = MarketplaceListing(
    id: listing.id,
    farmerProfileId: farmer.farmerProfileId,
    farmerName: farmer.farmerName,
    farmerAvatarUrl: farmer.farmerAvatarUrl,
    farmerLocationText: farmer.farmerLocationText,
    cropId: crop.cropId,
    cropName: crop.cropName,
    cropCategory: crop.cropCategory,
    listingImageUrl: listing.listingImageUrl,
    farmerCropImageUrl: crop.farmerCropImageUrl,
    cropFallbackImageUrl: crop.cropFallbackImageUrl,
    description: listing.description ?? crop.description,
    pricePerKg: listing.pricePerKg ?? crop.defaultPricePerKg ?? 0,
    availableQuantityKg: listing.availableQuantityKg,
    harvestedOn: listing.harvestedOn,
    publishedAt: listing.publishedAt,
  );
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ListingDetailScreen(
        listingId: listing.id,
        initialListing: initial,
        buyerProfile: buyerProfile,
      ),
    ),
  );
}

/// One crop on the farmer's menu. Tapping it goes straight to the
/// listing when there's exactly one batch to buy (the common case — no
/// point making the buyer pick from a list of one), and opens the batch
/// sheet otherwise (several prices/harvests to choose from, or nothing
/// buyable and only history to show).
class _CropTile extends StatefulWidget {
  final FarmerPublicCrop crop;
  final FarmerPublicProfile farmer;
  final Profile buyerProfile;

  const _CropTile({
    required this.crop,
    required this.farmer,
    required this.buyerProfile,
  });

  @override
  State<_CropTile> createState() => _CropTileState();
}

class _CropTileState extends State<_CropTile> {
  final _service = const FarmerPublicProfileService();
  bool _isOpening = false;

  Future<void> _onTap() async {
    if (_isOpening) return;
    setState(() => _isOpening = true);

    List<FarmerCropListing>? listings;
    try {
      listings = await _service.fetchCropListings(
        farmerProfileId: widget.farmer.farmerProfileId,
        cropId: widget.crop.cropId,
      );
    } catch (_) {
      // Fall through to the sheet, which fetches again and has its own
      // error/retry state — better than a silent dead tap.
    }
    if (!mounted) return;
    setState(() => _isOpening = false);

    final buyable = listings?.where((l) => l.isPurchasable).toList();
    if (buyable != null && buyable.length == 1) {
      _openListing(
        context,
        farmer: widget.farmer,
        crop: widget.crop,
        listing: buyable.single,
        buyerProfile: widget.buyerProfile,
      );
      return;
    }

    unawaited(
      _CropListingsSheet.show(
        context,
        farmer: widget.farmer,
        crop: widget.crop,
        buyerProfile: widget.buyerProfile,
        initialListings: listings,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final crop = widget.crop;
    final image = crop.displayImage;
    final available = crop.availableQuantityKg > 0;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: _onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 56,
                height: 56,
                child: MediaImage(
                  path: image.path,
                  bucket: image.bucket,
                  public: image.isFallback,
                  placeholder: Container(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: Icon(
                      Icons.eco_outlined,
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    crop.cropName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    available
                        ? '${crop.availableQuantityKg.toStringAsFixed(0)} kg available'
                        : 'Currently unavailable',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: available
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (crop.defaultPricePerKg != null)
              Text(
                'LKR ${crop.defaultPricePerKg!.toStringAsFixed(2)}/kg',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            const SizedBox(width: 4),
            // Same footprint as the chevron so the row doesn't jump.
            SizedBox(
              width: 20,
              height: 20,
              child: _isOpening
                  ? const Padding(
                      padding: EdgeInsets.all(2),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: theme.colorScheme.outline,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(icon, size: 32, color: theme.colorScheme.outline),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet showing every listing batch the farmer has published for
/// one crop — including past/inactive ones — with price and how much of
/// each is still left. Shown when a buyer taps a crop tile on the
/// profile; buyable batches open [ListingDetailScreen].
class _CropListingsSheet extends StatefulWidget {
  final FarmerPublicProfile farmer;
  final FarmerPublicCrop crop;
  final Profile buyerProfile;

  /// Already fetched by the tapped tile; when null (that fetch failed)
  /// the sheet fetches itself and shows its own error state.
  final List<FarmerCropListing>? initialListings;

  const _CropListingsSheet({
    required this.farmer,
    required this.crop,
    required this.buyerProfile,
    this.initialListings,
  });

  static Future<void> show(
    BuildContext context, {
    required FarmerPublicProfile farmer,
    required FarmerPublicCrop crop,
    required Profile buyerProfile,
    List<FarmerCropListing>? initialListings,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CropListingsSheet(
        farmer: farmer,
        crop: crop,
        buyerProfile: buyerProfile,
        initialListings: initialListings,
      ),
    );
  }

  @override
  State<_CropListingsSheet> createState() => _CropListingsSheetState();
}

class _CropListingsSheetState extends State<_CropListingsSheet> {
  final _service = const FarmerPublicProfileService();
  late Future<List<FarmerCropListing>> _future;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialListings;
    _future = initial != null ? Future.value(initial) : _fetch();
  }

  Future<List<FarmerCropListing>> _fetch() => _service.fetchCropListings(
    farmerProfileId: widget.farmer.farmerProfileId,
    cropId: widget.crop.cropId,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final crop = widget.crop;
    final image = crop.displayImage;
    final description = crop.description?.trim();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 64,
                      height: 64,
                      child: MediaImage(
                        path: image.path,
                        bucket: image.bucket,
                        public: image.isFallback,
                        placeholder: Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: Icon(
                            Icons.eco_outlined,
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          crop.cropName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          crop.availableQuantityKg > 0
                              ? '${crop.availableQuantityKg.toStringAsFixed(0)} kg available in total'
                              : 'Currently unavailable',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: crop.availableQuantityKg > 0
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (description != null && description.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(description, style: theme.textTheme.bodyMedium),
              ],
              const SizedBox(height: 16),
              Text(
                'Harvest batches',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: FutureBuilder<List<FarmerCropListing>>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (snapshot.hasError) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              "Couldn't load harvest batches.",
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            FilledButton.tonalIcon(
                              onPressed: () =>
                                  setState(() => _future = _fetch()),
                              icon: const Icon(Icons.refresh),
                              label: const Text('Retry'),
                            ),
                          ],
                        ),
                      );
                    }
                    final listings = snapshot.data ?? const [];
                    if (listings.isEmpty) {
                      return const _EmptyState(
                        icon: Icons.inventory_2_outlined,
                        message:
                            "This farmer hasn't added any harvest "
                            'batches for this crop yet.',
                      );
                    }
                    return ListView.separated(
                      shrinkWrap: true,
                      itemCount: listings.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) => _CropListingTile(
                        listing: listings[index],
                        farmer: widget.farmer,
                        crop: widget.crop,
                        buyerProfile: widget.buyerProfile,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CropListingTile extends StatelessWidget {
  final FarmerCropListing listing;
  final FarmerPublicProfile farmer;
  final FarmerPublicCrop crop;
  final Profile buyerProfile;

  const _CropListingTile({
    required this.listing,
    required this.farmer,
    required this.crop,
    required this.buyerProfile,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = listing.initialQuantityKg;
    final available = listing.availableQuantityKg;
    final fraction = initial <= 0 ? 0.0 : (available / initial).clamp(0, 1);
    final soldOut = available <= 0;
    // Has stock but was paused/expired by the farmer — not buyable either.
    final inactive = !soldOut && !listing.isPurchasable;
    final dimmed = soldOut || inactive;
    final description = listing.description?.trim();

    final tile = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: dimmed
            ? theme.colorScheme.surfaceContainerHighest
            : theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Opacity(
        opacity: dimmed ? 0.5 : 1,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Only a batch-specific photo is worth repeating here; the
            // crop's standing photo is already in the sheet header.
            if (listing.listingImageUrl != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: MediaImage(
                    path: listing.listingImageUrl,
                    bucket: 'crop-photos',
                    placeholder: Container(
                      color: theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          listing.harvestedOn != null
                              ? 'Harvested ${DateFormat('MMM d, yyyy').format(listing.harvestedOn!)}'
                              : 'Published ${DateFormat('MMM d, yyyy').format(listing.publishedAt)}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      if (listing.pricePerKg != null)
                        Text(
                          'LKR ${listing.pricePerKg!.toStringAsFixed(2)}/kg',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                  if (description != null && description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: fraction.toDouble(),
                            minHeight: 6,
                            backgroundColor:
                                theme.colorScheme.surfaceContainerHighest,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${available.toStringAsFixed(0)}/${initial.toStringAsFixed(0)} kg left',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (listing.isPurchasable) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: theme.colorScheme.outline,
              ),
            ],
          ],
        ),
      ),
    );

    return Stack(
      children: [
        if (listing.isPurchasable)
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _openListing(
              context,
              farmer: farmer,
              crop: crop,
              listing: listing,
              buyerProfile: buyerProfile,
            ),
            child: tile,
          )
        else
          tile,
        if (soldOut || inactive)
          Positioned.fill(
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  soldOut ? 'Sold out' : 'Not available',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

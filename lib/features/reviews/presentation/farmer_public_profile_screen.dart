import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/app_secondary_header.dart';
import '../../../core/widgets/avatar_image.dart';
import '../../../core/widgets/media_image.dart';
import '../../../models/farmer_public_profile.dart';
import '../../../models/farmer_review.dart';
import '../../../models/profile.dart';
import '../farmer_public_profile_service.dart';
import '../farmer_review_service.dart';
import 'widgets/review_dialog.dart';
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

  const FarmerPublicProfileScreen({
    super.key,
    required this.farmerProfileId,
    required this.buyerProfile,
    this.initialFarmerName,
    this.initialFarmerAvatarUrl,
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _buildHeaderCard(theme, profile),
        const SizedBox(height: 16),
        _ReviewCallToAction(
          buyerProfileId: widget.buyerProfile.id,
          farmerProfileId: profile.farmerProfileId,
          farmerName: profile.farmerName,
          onSubmitted: _reload,
        ),
        const SizedBox(height: 24),
        _buildSectionHeader(theme, 'Crops Grown'),
        const SizedBox(height: 12),
        if (profile.crops.isEmpty)
          const _EmptyState(
            icon: Icons.eco_outlined,
            message: "This farmer hasn't added any crops yet.",
          )
        else
          ...profile.crops.map(
            (crop) =>
                _CropTile(crop: crop, farmerProfileId: profile.farmerProfileId),
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
          ...profile.reviews.map((review) => _ReviewTile(review: review)),
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

class _CropTile extends StatelessWidget {
  final FarmerPublicCrop crop;
  final String farmerProfileId;

  const _CropTile({required this.crop, required this.farmerProfileId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final image = crop.displayImage;
    final available = crop.availableQuantityKg > 0;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _CropListingsSheet.show(
        context,
        farmerProfileId: farmerProfileId,
        crop: crop,
      ),
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
            Icon(
              Icons.chevron_right,
              size: 20,
              color: theme.colorScheme.outline,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  final FarmerPublicReview review;

  const _ReviewTile({required this.review});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  review.buyerName,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                DateFormat('MMM d, yyyy').format(review.createdAt),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          StarRatingDisplay(rating: review.rating.toDouble(), size: 16),
          if (review.comment != null && review.comment!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(review.comment!, style: theme.textTheme.bodyMedium),
          ],
        ],
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
/// one crop — including past/inactive ones — with how much of each is
/// still left. Shown when a buyer taps a crop tile on the profile.
class _CropListingsSheet extends StatefulWidget {
  final String farmerProfileId;
  final FarmerPublicCrop crop;

  const _CropListingsSheet({required this.farmerProfileId, required this.crop});

  static Future<void> show(
    BuildContext context, {
    required String farmerProfileId,
    required FarmerPublicCrop crop,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          _CropListingsSheet(farmerProfileId: farmerProfileId, crop: crop),
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
    _future = _service.fetchCropListings(
      farmerProfileId: widget.farmerProfileId,
      cropId: widget.crop.cropId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.crop.cropName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Harvest batches',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
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
                        child: Center(child: Text(snapshot.error.toString())),
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
                      itemBuilder: (context, index) =>
                          _CropListingTile(listing: listings[index]),
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

  const _CropListingTile({required this.listing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = listing.initialQuantityKg;
    final available = listing.availableQuantityKg;
    final fraction = initial <= 0 ? 0.0 : (available / initial).clamp(0, 1);
    final soldOut = available <= 0;

    return Stack(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: soldOut
                ? theme.colorScheme.surfaceContainerHighest
                : theme.colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Opacity(
            opacity: soldOut ? 0.5 : 1,
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
                    Text(
                      '${available.toStringAsFixed(0)}/${initial.toStringAsFixed(0)} kg',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: fraction.toDouble(),
                    minHeight: 6,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (soldOut)
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
                  'Sold out',
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

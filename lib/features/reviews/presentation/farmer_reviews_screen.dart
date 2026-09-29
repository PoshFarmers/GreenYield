import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../core/widgets/app_secondary_header.dart';
import '../farmer_review_service.dart';
import 'widgets/review_tile.dart';
import 'widgets/star_rating.dart';

/// All the reviews a farmer has received — opened from "See all
/// reviews" on their own profile. Summary + star breakdown on top
/// (tapping a bar filters to that rating), then every review, newest
/// first, shown exactly as buyers see them.
class FarmerReviewsScreen extends StatefulWidget {
  final String farmerProfileId;

  /// Already loaded by the profile card, so the screen opens instantly.
  final OwnReviews? initial;

  const FarmerReviewsScreen({
    super.key,
    required this.farmerProfileId,
    this.initial,
  });

  @override
  State<FarmerReviewsScreen> createState() => _FarmerReviewsScreenState();
}

class _FarmerReviewsScreenState extends State<FarmerReviewsScreen> {
  final _service = const FarmerReviewService();
  late Future<OwnReviews> _future;

  /// null = all ratings.
  int? _starFilter;

  @override
  void initState() {
    super.initState();
    _future = widget.initial != null
        ? Future.value(widget.initial)
        : _service.fetchOwnReviews(widget.farmerProfileId);
  }

  Future<void> _refresh() async {
    final next = _service.fetchOwnReviews(widget.farmerProfileId);
    setState(() => _future = next);
    await next;
  }

  void _toggleFilter(int star) =>
      setState(() => _starFilter = _starFilter == star ? null : star);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppSecondaryHeader(title: 'my_reviews'.tr()),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: FutureBuilder<OwnReviews>(
              future: _future,
              builder: (context, snapshot) {
                final data = snapshot.data;
                if (snapshot.hasError && data == null) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('reviews_load_failed'.tr()),
                        const SizedBox(height: 12),
                        FilledButton.tonalIcon(
                          onPressed: _refresh,
                          icon: const Icon(Icons.refresh),
                          label: Text('retry'.tr()),
                        ),
                      ],
                    ),
                  );
                }
                if (data == null) {
                  return const Center(child: CircularProgressIndicator());
                }

                final visible = _starFilter == null
                    ? data.reviews
                    : data.reviews
                          .where((r) => r.rating == _starFilter)
                          .toList();

                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      if (data.fromCache) ...[
                        const OfflineReviewsNotice(),
                        const SizedBox(height: 12),
                      ],
                      ReviewsSummary(
                        reviews: data,
                        selectedStar: _starFilter,
                        onStarTap: _toggleFilter,
                      ),
                      if (data.count > 0) ...[
                        const SizedBox(height: 16),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              ChoiceChip(
                                label: Text(
                                  '${'filter_all'.tr()} (${data.count})',
                                ),
                                selected: _starFilter == null,
                                onSelected: (_) =>
                                    setState(() => _starFilter = null),
                              ),
                              for (var star = 5; star >= 1; star--) ...[
                                const SizedBox(width: 8),
                                ChoiceChip(
                                  avatar: const Icon(Icons.star_rounded),
                                  label: Text(
                                    '$star (${data.distribution[star]})',
                                  ),
                                  selected: _starFilter == star,
                                  onSelected: (_) => _toggleFilter(star),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (data.count == 0)
                        const NoReviewsYet()
                      else if (visible.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 32),
                          child: Text(
                            'no_reviews_with_rating'.tr(),
                            textAlign: TextAlign.center,
                          ),
                        )
                      else
                        for (final review in visible) ...[
                          ReviewTile(
                            buyerName:
                                review.buyerName ??
                                'review_buyer_fallback'.tr(),
                            rating: review.rating,
                            comment: review.comment,
                            createdAt: review.createdAt,
                          ),
                          const SizedBox(height: 10),
                        ],
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Big average + stars + count, and a 5→1 star breakdown. Tapping a bar
/// calls [onStarTap] (used to filter); omit it for a static summary.
class ReviewsSummary extends StatelessWidget {
  final OwnReviews reviews;
  final int? selectedStar;
  final ValueChanged<int>? onStarTap;

  const ReviewsSummary({
    super.key,
    required this.reviews,
    this.selectedStar,
    this.onStarTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final distribution = reviews.distribution;
    final maxCount = distribution.values.fold<int>(0, (a, b) => a > b ? a : b);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          children: [
            Text(
              reviews.count == 0 ? '–' : reviews.average.toStringAsFixed(1),
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            StarRatingDisplay(rating: reviews.average, size: 16),
            const SizedBox(height: 4),
            Text(
              'n_reviews'.plural(reviews.count),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            children: [
              for (var star = 5; star >= 1; star--)
                InkWell(
                  onTap: onStarTap == null || reviews.count == 0
                      ? null
                      : () => onStarTap!(star),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 14,
                          child: Text(
                            '$star',
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: selectedStar == star
                                  ? FontWeight.bold
                                  : null,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.star_rounded,
                          size: 14,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: maxCount == 0
                                  ? 0
                                  : distribution[star]! / maxCount,
                              minHeight: 8,
                              backgroundColor:
                                  theme.colorScheme.surfaceContainerHighest,
                              color:
                                  selectedStar == null || selectedStar == star
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.primary.withValues(
                                      alpha: 0.35,
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 24,
                          child: Text(
                            '${distribution[star]}',
                            textAlign: TextAlign.end,
                            style: theme.textTheme.labelMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class NoReviewsYet extends StatelessWidget {
  const NoReviewsYet({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(
            Icons.rate_review_outlined,
            size: 40,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 10),
          Text(
            'no_reviews_yet'.tr(),
            style: theme.textTheme.titleSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'no_reviews_yet_farmer_hint'.tr(),
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class OfflineReviewsNotice extends StatelessWidget {
  const OfflineReviewsNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 18,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'reviews_offline_notice'.tr(),
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

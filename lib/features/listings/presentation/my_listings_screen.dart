import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_header.dart';
import '../../../core/widgets/media_image.dart';
import '../../../models/produce_listing.dart';
import '../../../models/profile.dart';
import '../../pricing/presentation/widgets/market_price_comparison_card.dart';
import '../produce_listing_service.dart';
import 'add_harvest_screen.dart';

/// Farmer's "Harvest" tab — their own produce listings, with summary
/// stats and a status filter. Posting a new listing (the FAB) is the
/// next piece of work; see CROP_AND_LISTING_DESIGN.md §2 step 3.
class MyListingsScreen extends ConsumerStatefulWidget {
  final Profile profile;

  const MyListingsScreen({super.key, required this.profile});

  @override
  ConsumerState<MyListingsScreen> createState() => _MyListingsScreenState();
}

class _MyListingsScreenState extends ConsumerState<MyListingsScreen> {
  final _service = ProduceListingService();
  final _scrollController = ScrollController();

  late final Stream<List<ProduceListing>> _listingsStream;
  String _statusFilter = 'all';
  bool _statsCollapsed = false;

  @override
  void initState() {
    super.initState();
    _listingsStream = _service.watchOwnListings(widget.profile.id);
    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  // Hysteresis so the section doesn't flicker while sitting right at the
  // threshold — collapse past 24px, only restore once back under 8px.
  void _handleScroll() {
    final offset = _scrollController.offset;
    if (!_statsCollapsed && offset > 24) {
      setState(() => _statsCollapsed = true);
    } else if (_statsCollapsed && offset < 8) {
      setState(() => _statsCollapsed = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppHeader(profile: widget.profile),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AddHarvestScreen(profile: widget.profile),
          ),
        ),
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: StreamBuilder<List<ProduceListing>>(
              stream: _listingsStream,
              builder: (context, snapshot) {
                if (!snapshot.hasData && !snapshot.hasError) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text(snapshot.error.toString()));
                }

                final listings = snapshot.data ?? [];
                final visible = _statusFilter == 'all'
                    ? listings
                    : listings.where((l) => l.status == _statusFilter).toList();

                return ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                  children: [
                    Text(
                      'my_listings_title'.tr(),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'my_listings_subtitle'.tr(),
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    _StatsSection(
                      listings: listings,
                      collapsed: _statsCollapsed,
                    ),
                    const SizedBox(height: 16),
                    _StatusFilterBar(
                      listings: listings,
                      selected: _statusFilter,
                      onSelected: (value) =>
                          setState(() => _statusFilter = value),
                    ),
                    const SizedBox(height: 16),
                    if (visible.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 48),
                        child: Column(
                          children: [
                            Icon(
                              Icons.grass_outlined,
                              size: 48,
                              color: theme.colorScheme.outline,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'no_listings_yet'.tr(),
                              style: theme.textTheme.bodyMedium,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    else
                      for (final listing in visible) ...[
                        _ListingCard(listing: listing),
                        const SizedBox(height: 12),
                      ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// The four summary tiles. Auto-collapses (shrinks + fades) once the user
/// scrolls down through their listings, and restores near the top — see
/// _MyListingsScreenState._handleScroll.
class _StatsSection extends StatelessWidget {
  final List<ProduceListing> listings;
  final bool collapsed;

  const _StatsSection({required this.listings, required this.collapsed});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final active = listings.where((l) => l.status == 'active').toList();
    final soldOut = listings.where((l) => l.status == 'sold_out').length;
    final totalKg = active.fold<double>(
      0,
      (sum, l) => sum + l.availableQuantityKg,
    );
    final totalValue = active.fold<double>(0, (sum, l) => sum + l.totalValue);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text('overview'.tr(), style: theme.textTheme.labelLarge),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 220),
            opacity: collapsed ? 0 : 1,
            child: collapsed
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _StatTile(
                                icon: Icons.inventory_2_outlined,
                                label: 'stat_active'.tr(),
                                value: '${active.length}',
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _StatTile(
                                icon: Icons.remove_shopping_cart_outlined,
                                label: 'stat_sold_out'.tr(),
                                value: '$soldOut',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _StatTile(
                                icon: Icons.scale_outlined,
                                label: 'stat_listed_quantity'.tr(),
                                value: '${totalKg.toStringAsFixed(0)} kg',
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _StatTile(
                                icon: Icons.payments_outlined,
                                label: 'stat_listed_value'.tr(),
                                value: 'Rs ${totalValue.toStringAsFixed(0)}',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(height: 8),
          Text(label, style: theme.textTheme.bodySmall),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusFilterBar extends StatelessWidget {
  final List<ProduceListing> listings;
  final String selected;
  final ValueChanged<String> onSelected;

  const _StatusFilterBar({
    required this.listings,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    int countOf(String status) =>
        listings.where((l) => l.status == status).length;

    final filters = <(String, String)>[
      ('all', '${'filter_all'.tr()} (${listings.length})'),
      ('active', '${'status_active'.tr()} (${countOf('active')})'),
      ('sold_out', '${'status_sold_out'.tr()} (${countOf('sold_out')})'),
      ('expired', '${'status_expired'.tr()} (${countOf('expired')})'),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (value, label) in filters) ...[
            ChoiceChip(
              label: Text(label),
              selected: selected == value,
              onSelected: (_) => onSelected(value),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _ListingCard extends StatelessWidget {
  final ProduceListing listing;

  const _ListingCard({required this.listing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderRadius = BorderRadius.circular(16);

    return Stack(
      children: [
        ClipRRect(
          borderRadius: borderRadius,
          child: Container(
            color: theme.colorScheme.surfaceContainerLowest,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Stack(
                  children: [
                    SizedBox(
                      height: 150,
                      width: double.infinity,
                      child: MediaImage(
                        path: listing.displayImage.path,
                        bucket: listing.displayImage.bucket,
                        public: listing.displayImage.isFallback,
                        placeholder: Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: Icon(
                            Icons.image_outlined,
                            size: 40,
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 10,
                      left: 10,
                      child: _StatusBadge(status: listing.status),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        listing.cropName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (listing.description != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          listing.description!,
                          style: theme.textTheme.bodySmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const Divider(height: 24),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'price_per_kg'.tr(),
                                style: theme.textTheme.bodySmall,
                              ),
                              Text(
                                'Rs ${listing.pricePerKg.toStringAsFixed(2)}',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              MarketPriceComparisonCard(
                                cropId: listing.cropId,
                                farmerPricePerKg: listing.pricePerKg,
                                compact: true,
                              ),
                            ],
                          ),
                          const Spacer(),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                'stock_available'.tr(),
                                style: theme.textTheme.bodySmall,
                              ),
                              Text(
                                '${listing.availableQuantityKg.toStringAsFixed(0)} kg',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // Painted on top so the border is never covered at the rounded
        // corners (the image otherwise sits flush against the top edge
        // with nothing to buffer it).
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (color, labelKey) = switch (status) {
      'active' => (theme.colorScheme.primary, 'status_active'),
      'sold_out' => (theme.colorScheme.error, 'status_sold_out'),
      'expired' => (theme.colorScheme.outline, 'status_expired'),
      _ => (theme.colorScheme.tertiary, 'status_flagged'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        labelKey.tr(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

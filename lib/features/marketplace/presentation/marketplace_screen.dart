import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_header.dart';
import '../../../core/widgets/avatar_image.dart';
import '../../../core/widgets/media_image.dart';
import '../../../models/marketplace_listing.dart';
import '../../../models/profile.dart';
import '../marketplace_service.dart';
import 'listing_detail_screen.dart';

/// Buyer home — the marketplace feed of every farmer's active listings.
///
/// Server-queried rather than PowerSync-backed (see MarketplaceService),
/// so unlike the rest of the app it needs a connection and has a real
/// error state.
class MarketplaceScreen extends ConsumerStatefulWidget {
  final Profile profile;

  const MarketplaceScreen({super.key, required this.profile});

  @override
  ConsumerState<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends ConsumerState<MarketplaceScreen> {
  static const _pageSize = 20;
  static const _debounce = Duration(milliseconds: 350);

  final _service = const MarketplaceService();
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  Timer? _debounceTimer;

  List<MarketplaceListing> _listings = [];
  List<MarketplaceFarmer> _farmers = [];
  String _query = '';
  String? _category;
  MarketplaceFarmer? _farmerFilter;

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  /// The farmers row is discovery-only, so it's fetched just for the
  /// unfiltered browse state.
  bool get _showFarmersRow =>
      _query.isEmpty && _category == null && _farmerFilter == null;

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await _service.search(
        query: _query,
        category: _category,
        farmerId: _farmerFilter?.farmerProfileId,
        buyerLocation: widget.profile.locationPoint,
        limit: _pageSize,
      );

      // Only refetch farmers when the discovery row is actually visible.
      final farmers = _showFarmersRow
          ? await _service.farmers(buyerLocation: widget.profile.locationPoint)
          : _farmers;

      if (!mounted) return;
      setState(() {
        _listings = results;
        _farmers = farmers;
        _hasMore = results.length == _pageSize;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore || _isLoading) return;
    setState(() => _isLoadingMore = true);

    try {
      final more = await _service.search(
        query: _query,
        category: _category,
        farmerId: _farmerFilter?.farmerProfileId,
        buyerLocation: widget.profile.locationPoint,
        limit: _pageSize,
        offset: _listings.length,
      );

      if (!mounted) return;
      setState(() {
        _listings = [..._listings, ...more];
        _hasMore = more.length == _pageSize;
        _isLoadingMore = false;
      });
    } catch (_) {
      // A failed page-append shouldn't blow away results already on
      // screen — just stop paging.
      if (!mounted) return;
      setState(() {
        _isLoadingMore = false;
        _hasMore = false;
      });
    }
  }

  void _onQueryChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, () {
      if (!mounted) return;
      setState(() => _query = value.trim());
      _load();
    });
  }

  void _setCategory(String? category) {
    setState(() => _category = category);
    _load();
  }

  void _toggleFarmerFilter(MarketplaceFarmer farmer) {
    setState(() {
      _farmerFilter = _farmerFilter?.farmerProfileId == farmer.farmerProfileId
          ? null
          : farmer;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppHeader(profile: widget.profile),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: RefreshIndicator(
              onRefresh: _load,
              child: CustomScrollView(
                controller: _scrollController,
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    sliver: SliverList.list(
                      children: [
                        TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'marketplace_search_hint'.tr(),
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _searchController.text.isEmpty
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.close),
                                    onPressed: () {
                                      _searchController.clear();
                                      _onQueryChanged('');
                                    },
                                  ),
                          ),
                          onChanged: (value) {
                            setState(() {}); // refresh the clear button
                            _onQueryChanged(value);
                          },
                        ),
                        const SizedBox(height: 12),
                        _CategoryChips(
                          selected: _category,
                          onSelected: _setCategory,
                        ),
                        if (_farmerFilter != null) ...[
                          const SizedBox(height: 12),
                          InputChip(
                            avatar: const Icon(Icons.person_outline, size: 18),
                            label: Text(_farmerFilter!.farmerName),
                            onDeleted: () =>
                                _toggleFarmerFilter(_farmerFilter!),
                          ),
                        ],
                        if (_showFarmersRow && _farmers.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          _FarmersRow(
                            farmers: _farmers,
                            onTap: _toggleFarmerFilter,
                          ),
                        ],
                        const SizedBox(height: 16),
                        Text(
                          _query.isEmpty
                              ? 'fresh_today'.tr()
                              : 'search_results'.tr(),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                  ..._buildBody(),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildBody() {
    if (_isLoading) {
      return const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 60),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      ];
    }

    if (_errorMessage != null) {
      return [
        SliverToBoxAdapter(
          child: _ErrorState(message: _errorMessage!, onRetry: _load),
        ),
      ];
    }

    if (_listings.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 60),
            child: Column(
              children: [
                Icon(
                  Icons.storefront_outlined,
                  size: 48,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(height: 12),
                Text(
                  'no_produce_found'.tr(),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      ];
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverGrid.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.72,
          ),
          itemCount: _listings.length,
          itemBuilder: (context, index) {
            final listing = _listings[index];
            return _ListingCard(
              listing: listing,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ListingDetailScreen(
                    listingId: listing.id,
                    initialListing: listing,
                    buyerProfile: widget.profile,
                  ),
                ),
              ),
            );
          },
        ),
      ),
      if (_isLoadingMore)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
    ];
  }
}

class _CategoryChips extends StatelessWidget {
  final String? selected;
  final ValueChanged<String?> onSelected;

  const _CategoryChips({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    // Only vegetable/fruit exist in the crop_category enum — the
    // mockup's "Grains" chip has no schema backing.
    const options = <(String?, String)>[
      (null, 'category_all'),
      ('vegetable', 'crop_category_vegetable'),
      ('fruit', 'crop_category_fruit'),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (value, labelKey) in options) ...[
            ChoiceChip(
              label: Text(labelKey.tr()),
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

class _FarmersRow extends StatelessWidget {
  final List<MarketplaceFarmer> farmers;
  final ValueChanged<MarketplaceFarmer> onTap;

  const _FarmersRow({required this.farmers, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'farmers_near_you'.tr(),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 108,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: farmers.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final farmer = farmers[index];
              return InkWell(
                onTap: () => onTap(farmer),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: 190,
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
                          AvatarImage(path: farmer.farmerAvatarUrl, radius: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  farmer.farmerName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (farmer.farmerLocationText != null)
                                  Text(
                                    farmer.farmerLocationText!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall,
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 4,
                        children: farmer.cropNames
                            .take(2)
                            .map(
                              (name) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      theme.colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  name,
                                  style: theme.textTheme.labelSmall,
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ListingCard extends StatelessWidget {
  final MarketplaceListing listing;
  final VoidCallback onTap;

  const _ListingCard({required this.listing, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 5,
              child: MediaImage(
                path: listing.imageUrl,
                bucket: 'crop-photos',
                placeholder: Container(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Icon(
                    Icons.image_outlined,
                    size: 32,
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 5,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      listing.cropName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${'currency_prefix'.tr()} ${listing.pricePerKg.toStringAsFixed(2)} / ${'kg'.tr()}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Icon(
                          Icons.person_outline,
                          size: 13,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            listing.farmerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                    if (listing.distanceKm != null)
                      Row(
                        children: [
                          Icon(
                            Icons.place_outlined,
                            size: 13,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${listing.distanceKm!.toStringAsFixed(1)} km',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 48,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            'marketplace_load_failed'.tr(),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: Text('retry'.tr()),
          ),
        ],
      ),
    );
  }
}

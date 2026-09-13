import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_header.dart';
import '../../../core/widgets/avatar_image.dart';
import '../../../models/marketplace_listing.dart';
import '../../../models/profile.dart';
import '../marketplace_service.dart';
import 'listing_detail_screen.dart';
import 'produce_card.dart';

enum _MarketTab { produce, farmers }

/// Sort field *and* direction bundled into one option, each with its own
/// unambiguous label ("Price: Low to High" rather than a bare "Price"
/// chip plus a separate up/down toggle) — picking one is a single,
/// legible choice about what's prioritized, shown via radio buttons in
/// the filter sheet rather than a scattering of ticks.
enum _SortOption {
  priceLowHigh(Icons.trending_up, 'sort_price_low_high'),
  priceHighLow(Icons.trending_down, 'sort_price_high_low'),
  distanceNearest(Icons.near_me_outlined, 'sort_distance_nearest'),
  harvestedNewest(Icons.event_outlined, 'sort_harvested_newest'),
  harvestedOldest(Icons.event_busy_outlined, 'sort_harvested_oldest'),
  stockMostFirst(Icons.inventory_2_outlined, 'sort_stock_most'),
  stockLeastFirst(Icons.production_quantity_limits, 'sort_stock_least');

  final IconData icon;
  final String labelKey;

  const _SortOption(this.icon, this.labelKey);
}

/// Buyer home — the marketplace feed of every farmer's active listings,
/// plus a dedicated tab for browsing farmers directly.
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
  static const _farmerPageSize = 50;
  static const _debounce = Duration(milliseconds: 350);

  final _service = const MarketplaceService();
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  Timer? _debounceTimer;

  _MarketTab _tab = _MarketTab.produce;

  List<MarketplaceListing> _listings = [];
  List<MarketplaceFarmer> _farmers = [];
  String _query = '';
  String? _category;
  MarketplaceFarmer? _farmerFilter;

  // Produce sort/filter — applied client-side to the page(s) already
  // fetched, since the search RPC doesn't take a sort/stock param yet.
  _SortOption _sortOption = _SortOption.priceLowHigh;
  double _minStockKg = 0;

  bool _farmersSortAscending = true;

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
    if (_tab != _MarketTab.produce) return;
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (_tab == _MarketTab.produce) {
        final results = await _service.search(
          query: _query,
          category: _category,
          farmerId: _farmerFilter?.farmerProfileId,
          buyerLocation: widget.profile.locationPoint,
          limit: _pageSize,
        );
        if (!mounted) return;
        setState(() {
          _listings = results;
          _hasMore = results.length == _pageSize;
          _isLoading = false;
        });
      } else {
        final farmers = await _service.farmers(
          buyerLocation: widget.profile.locationPoint,
          limit: _farmerPageSize,
        );
        if (!mounted) return;
        setState(() {
          _farmers = farmers;
          _isLoading = false;
        });
      }
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
      // The farmers tab filters its already-fetched list client-side —
      // no need to re-hit the network on every keystroke.
      if (_tab == _MarketTab.produce) _load();
    });
  }

  void _setTab(_MarketTab tab) {
    if (tab == _tab) return;
    setState(() {
      _tab = tab;
      _query = '';
      _searchController.clear();
      _category = null;
      _farmerFilter = null;
    });
    _load();
  }

  void _setCategory(String? category) {
    setState(() => _category = category);
    _load();
  }

  void _clearFarmerFilter() {
    setState(() => _farmerFilter = null);
    _load();
  }

  /// Jumps from a farmer row (Farmers tab) to their produce, filtered.
  void _viewFarmerProduce(MarketplaceFarmer farmer) {
    setState(() {
      _tab = _MarketTab.produce;
      _farmerFilter = farmer;
      _query = '';
      _searchController.clear();
      _category = null;
    });
    _load();
  }

  List<MarketplaceListing> get _visibleListings {
    final list = _minStockKg > 0
        ? _listings.where((l) => l.availableQuantityKg >= _minStockKg).toList()
        : List.of(_listings);

    // Nulls (no harvest date recorded / no distance available) always
    // sort to the end, regardless of which direction is chosen.
    int nullsLast(Comparable? a, Comparable? b) {
      if (a == null && b == null) return 0;
      if (a == null) return 1;
      if (b == null) return -1;
      return a.compareTo(b);
    }

    switch (_sortOption) {
      case _SortOption.priceLowHigh:
        list.sort((a, b) => a.pricePerKg.compareTo(b.pricePerKg));
      case _SortOption.priceHighLow:
        list.sort((a, b) => b.pricePerKg.compareTo(a.pricePerKg));
      case _SortOption.distanceNearest:
        list.sort((a, b) => nullsLast(a.distanceKm, b.distanceKm));
      case _SortOption.harvestedNewest:
        list.sort((a, b) => nullsLast(b.harvestedOn, a.harvestedOn));
      case _SortOption.harvestedOldest:
        list.sort((a, b) => nullsLast(a.harvestedOn, b.harvestedOn));
      case _SortOption.stockMostFirst:
        list.sort(
          (a, b) => b.availableQuantityKg.compareTo(a.availableQuantityKg),
        );
      case _SortOption.stockLeastFirst:
        list.sort(
          (a, b) => a.availableQuantityKg.compareTo(b.availableQuantityKg),
        );
    }
    return list;
  }

  List<MarketplaceFarmer> get _visibleFarmers {
    final q = _query.toLowerCase();
    final list =
        _farmers
            .where((f) => q.isEmpty || f.farmerName.toLowerCase().contains(q))
            .toList()
          ..sort(
            (a, b) => a.farmerName.toLowerCase().compareTo(
              b.farmerName.toLowerCase(),
            ),
          );
    if (!_farmersSortAscending) return list.reversed.toList();
    return list;
  }

  Future<void> _openFilterSheet() async {
    var option = _sortOption;
    var minStock = _minStockKg;
    final hasDistance = widget.profile.locationPoint != null;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final theme = Theme.of(sheetContext);
          final options = _SortOption.values.where(
            (o) => hasDistance || o != _SortOption.distanceNearest,
          );

          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'filter_and_sort'.tr(),
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text('sort_by'.tr(), style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 8),
                  // Each row is one complete, unambiguous priority
                  // ("Price: Low to High") rather than a field chip plus
                  // a separate direction toggle — a radio group makes
                  // the single active choice obvious at a glance.
                  ...options.map(
                    (o) => _SortOptionTile(
                      option: o,
                      selected: option == o,
                      onTap: () => setSheetState(() => option = o),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 16),
                  Text(
                    'minimum_stock'.tr(
                      namedArgs: {'value': minStock.toStringAsFixed(0)},
                    ),
                    style: theme.textTheme.labelLarge,
                  ),
                  Slider(
                    value: minStock,
                    min: 0,
                    max: 200,
                    divisions: 20,
                    label: minStock.toStringAsFixed(0),
                    onChanged: (value) => setSheetState(() => minStock = value),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => setSheetState(() {
                            option = _SortOption.priceLowHigh;
                            minStock = 0;
                          }),
                          child: Text('reset_filters'.tr()),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _sortOption = option;
                              _minStockKg = minStock;
                            });
                            Navigator.of(sheetContext).pop();
                          },
                          child: Text('apply_filters'.tr()),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppHeader(profile: widget.profile),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: _MarketTabBar(selected: _tab, onSelected: _setTab),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _load,
                    child: _tab == _MarketTab.produce
                        ? _buildProduceBody()
                        : _buildFarmersBody(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProduceBody() {
    final theme = Theme.of(context);
    final visible = _isLoading || _errorMessage != null
        ? const <MarketplaceListing>[]
        : _visibleListings;

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          sliver: SliverList.list(
            children: [
              _EvenSegments(
                selected: _category,
                onSelected: _setCategory,
                options: const [
                  (null, 'crop_category_all'),
                  ('fruit', 'crop_category_fruit'),
                  ('vegetable', 'crop_category_vegetable'),
                ],
              ),
              const SizedBox(height: 12),
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
              if (_farmerFilter != null) ...[
                const SizedBox(height: 12),
                InputChip(
                  avatar: const Icon(Icons.person_outline, size: 18),
                  label: Text(_farmerFilter!.farmerName),
                  onDeleted: _clearFarmerFilter,
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'items_count'.tr(
                        namedArgs: {'count': '${visible.length}'},
                      ),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _SortPillButton(
                    icon: _sortOption.icon,
                    label: _sortOption.labelKey.tr(),
                    highlighted: _minStockKg > 0,
                    onTap: _openFilterSheet,
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
        ..._buildProduceGrid(visible),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  List<Widget> _buildProduceGrid(List<MarketplaceListing> visible) {
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

    if (visible.isEmpty) {
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
            crossAxisCount: 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 0.66,
          ),
          itemCount: visible.length,
          itemBuilder: (context, index) {
            final listing = visible[index];
            return ProduceCard(
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

  Widget _buildFarmersBody() {
    final theme = Theme.of(context);
    final visible = _isLoading || _errorMessage != null
        ? const <MarketplaceFarmer>[]
        : _visibleFarmers;

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          sliver: SliverList.list(
            children: [
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'search_farmers_hint'.tr(),
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
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'farmers_count'.tr(
                        namedArgs: {'count': '${visible.length}'},
                      ),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'sort_ascending'.tr(),
                    icon: const Icon(Icons.arrow_upward),
                    color: _farmersSortAscending
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline,
                    onPressed: () =>
                        setState(() => _farmersSortAscending = true),
                  ),
                  IconButton(
                    tooltip: 'sort_descending'.tr(),
                    icon: const Icon(Icons.arrow_downward),
                    color: !_farmersSortAscending
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline,
                    onPressed: () =>
                        setState(() => _farmersSortAscending = false),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
        ..._buildFarmersList(visible),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  List<Widget> _buildFarmersList(List<MarketplaceFarmer> visible) {
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

    if (visible.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 60),
            child: Column(
              children: [
                Icon(
                  Icons.people_outline,
                  size: 48,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(height: 12),
                Text(
                  'no_farmers_found'.tr(),
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
        sliver: SliverList.separated(
          itemCount: visible.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final farmer = visible[index];
            return _FarmerRow(
              farmer: farmer,
              onTap: () => _viewFarmerProduce(farmer),
            );
          },
        ),
      ),
    ];
  }
}

/// Top-of-page toggle between browsing produce and browsing farmers.
/// Always exactly one segment selected.
class _MarketTabBar extends StatelessWidget {
  final _MarketTab selected;
  final ValueChanged<_MarketTab> onSelected;

  const _MarketTabBar({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<_MarketTab>(
      segments: [
        ButtonSegment(
          value: _MarketTab.produce,
          label: Text('tab_produce'.tr()),
          icon: const Icon(Icons.eco_outlined),
        ),
        ButtonSegment(
          value: _MarketTab.farmers,
          label: Text('tab_farmers'.tr()),
          icon: const Icon(Icons.people_outline),
        ),
      ],
      selected: {selected},
      showSelectedIcon: false,
      onSelectionChanged: (values) => onSelected(values.first),
      style: SegmentedButton.styleFrom(
        minimumSize: const Size(double.infinity, 44),
      ),
    );
  }
}

/// Evenly-spread category segments (All / Fruits / Vegetables) — unlike
/// a horizontally-scrolling chip row, each option gets equal width.
class _EvenSegments extends StatelessWidget {
  final String? selected;
  final ValueChanged<String?> onSelected;
  final List<(String?, String)> options;

  const _EvenSegments({
    required this.selected,
    required this.onSelected,
    required this.options,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        for (final (value, labelKey) in options) ...[
          if (value != options.first.$1) const SizedBox(width: 8),
          Expanded(
            child: _SegmentButton(
              label: labelKey.tr(),
              selected: selected == value,
              onTap: () => onSelected(value),
              theme: theme,
            ),
          ),
        ],
      ],
    );
  }
}

class _SegmentButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final ThemeData theme;

  const _SegmentButton({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelLarge?.copyWith(
            color: selected
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// One farmer, shown as a full-width row (Farmers tab) rather than the
/// compact horizontal-scroll card used elsewhere.
class _FarmerRow extends StatelessWidget {
  final MarketplaceFarmer farmer;
  final VoidCallback onTap;

  const _FarmerRow({required this.farmer, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            AvatarImage(path: farmer.farmerAvatarUrl, radius: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    farmer.farmerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (farmer.farmerLocationText != null) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          Icons.place_outlined,
                          size: 13,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            farmer.farmerLocationText!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        if (farmer.distanceKm != null) ...[
                          const SizedBox(width: 6),
                          Text(
                            '${farmer.distanceKm!.toStringAsFixed(1)} km',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ],
                  if (farmer.cropNames.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: farmer.cropNames
                          .take(3)
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
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact "current sort" pill next to the item count — tapping it opens
/// the filter sheet. Shows the active priority's icon + label so the
/// user always sees what's driving the order, not just a bare icon.
class _SortPillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool highlighted;
  final VoidCallback onTap;

  const _SortPillButton({
    required this.icon,
    required this.label,
    required this.highlighted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = highlighted
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: highlighted
              ? theme.colorScheme.primary.withValues(alpha: 0.1)
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down, size: 18, color: color),
          ],
        ),
      ),
    );
  }
}

/// One row in the filter sheet's sort list — a full priority ("Price:
/// Low to High"), selected like a radio group so exactly one is ever
/// active and it's obvious which.
class _SortOptionTile extends StatelessWidget {
  final _SortOption option;
  final bool selected;
  final VoidCallback onTap;

  const _SortOptionTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            Icon(
              option.icon,
              size: 20,
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                option.labelKey.tr(),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  color: selected ? theme.colorScheme.primary : null,
                ),
              ),
            ),
            Radio<bool>(
              value: true,
              groupValue: selected ? true : null,
              onChanged: (_) => onTap(),
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

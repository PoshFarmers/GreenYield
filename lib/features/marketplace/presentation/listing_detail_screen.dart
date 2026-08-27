import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/avatar_image.dart';
import '../../../core/widgets/media_image.dart';
import '../../../models/marketplace_listing.dart';
import '../../../models/profile.dart';
import '../../cart/cart_service.dart';
import '../../navigation/presentation/app_nav_shell.dart';
import '../../pricing/presentation/widgets/price_breakdown_card.dart';
import '../marketplace_service.dart';

/// Full detail for one listing, with the quantity stepper and the entry
/// point into a conversation with the farmer.
///
/// [initialListing] is the row already in hand from the feed, shown
/// immediately while the fresh copy loads — stock and price can have
/// moved since the feed was fetched.
class ListingDetailScreen extends ConsumerStatefulWidget {
  final String listingId;
  final MarketplaceListing? initialListing;
  final Profile buyerProfile;

  /// Index of the Chat tab in the buyer's nav shell
  /// (Home, Cart, Orders, Chat) — see role_nav_shell_registry.dart.
  static const chatTabIndex = 3;

  const ListingDetailScreen({
    super.key,
    required this.listingId,
    required this.buyerProfile,
    this.initialListing,
  });

  @override
  ConsumerState<ListingDetailScreen> createState() =>
      _ListingDetailScreenState();
}

class _ListingDetailScreenState extends ConsumerState<ListingDetailScreen> {
  final _service = const MarketplaceService();
  final _cartService = const CartService();

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  MarketplaceListing? _listing;
  double _quantity = 1;
  bool _isLoading = true;
  bool _isOffline = false;
  bool _isAddingToCart = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _listing = widget.initialListing;
    _isLoading = widget.initialListing == null;

    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      if (!mounted) return;
      setState(() => _isOffline = results.contains(ConnectivityResult.none));
    });

    _load();
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final fresh = await _service.getListing(
        widget.listingId,
        buyerLocation: widget.buyerProfile.locationPoint,
      );
      if (!mounted) return;
      setState(() {
        if (fresh != null) _listing = fresh;
        _quantity = _clampQuantity(_quantity);
        _isLoading = false;
        _errorMessage = fresh == null ? 'listing_unavailable'.tr() : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        // Keep showing the feed's copy if we have one; only surface the
        // error when there's nothing at all to display.
        if (_listing == null) _errorMessage = e.toString();
      });
    }
  }

  double get _maxQuantity => _listing?.availableQuantityKg ?? 0;

  double _clampQuantity(double value) {
    if (_maxQuantity <= 0) return 0;
    return value.clamp(1, _maxQuantity).toDouble();
  }

  void _changeQuantity(double delta) {
    setState(() => _quantity = _clampQuantity(_quantity + delta));
  }

  Future<void> _addToCart(MarketplaceListing listing) async {
    if (_isAddingToCart) return;
    setState(() => _isAddingToCart = true);
    try {
      await _cartService.addToCart(
        buyerProfileId: widget.buyerProfile.id,
        produceListingId: listing.id,
        quantityKg: _quantity,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('added_to_cart'.tr())));
    } finally {
      if (mounted) setState(() => _isAddingToCart = false);
    }
  }

  void _messageFarmer() {
    // Chat isn't built yet — this only performs the transition, landing
    // the buyer on the Chat tab of the shell underneath.
    Navigator.of(context).popUntil((route) => route.isFirst);
    ref
        .read(navShellIndexProvider.notifier)
        .select(ListingDetailScreen.chatTabIndex);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final listing = _listing;

    return Scaffold(
      appBar: AppBar(
        title: Text('listing'.tr()),
        actions: [
          IconButton(icon: const Icon(Icons.help_outline), onPressed: () {}),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : listing == null
                ? _buildError(theme)
                : _buildContent(theme, listing),
          ),
        ),
      ),
    );
  }

  Widget _buildError(ThemeData theme) {
    return Padding(
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
          Text(
            _errorMessage ?? 'listing_unavailable'.tr(),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: () {
              setState(() => _isLoading = true);
              _load();
            },
            icon: const Icon(Icons.refresh),
            label: Text('retry'.tr()),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(ThemeData theme, MarketplaceListing listing) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        if (_isOffline) _OfflineBanner(theme: theme),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 220,
            width: double.infinity,
            child: MediaImage(
              path: listing.imageUrl,
              bucket: 'crop-photos',
              placeholder: Container(
                color: theme.colorScheme.surfaceContainerHighest,
                child: Icon(
                  Icons.image_outlined,
                  size: 48,
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Title + price
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    listing.cropName,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (listing.farmerLocationText != null) ...[
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
                            listing.farmerLocationText!,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${'currency_prefix'.tr()} ${listing.pricePerKg.toStringAsFixed(2)}',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text('per_kg'.tr(), style: theme.textTheme.bodySmall),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),

        Row(
          children: [
            Expanded(
              child: _InfoTile(
                icon: Icons.inventory_2_outlined,
                label: 'available_stock'.tr(),
                value:
                    '${listing.availableQuantityKg.toStringAsFixed(0)} ${'kg'.tr()}',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _InfoTile(
                icon: Icons.event_outlined,
                label: 'harvest_date'.tr(),
                value: listing.harvestedOn == null
                    ? '—'
                    : _formatDate(listing.harvestedOn!),
              ),
            ),
          ],
        ),

        if (listing.description != null &&
            listing.description!.trim().isNotEmpty) ...[
          const SizedBox(height: 16),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'about_this_crop'.tr(),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(listing.description!, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],

        const SizedBox(height: 16),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'order_quantity'.tr(),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              if (listing.isSoldOut)
                Text(
                  'sold_out_message'.tr(),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                )
              else ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton.filledTonal(
                      onPressed: _quantity <= 1
                          ? null
                          : () => _changeQuantity(-1),
                      icon: const Icon(Icons.remove),
                    ),
                    Column(
                      children: [
                        Text(
                          _quantity.toStringAsFixed(0),
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'kilograms'.tr(),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                    IconButton.filledTonal(
                      onPressed: _quantity >= _maxQuantity
                          ? null
                          : () => _changeQuantity(1),
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                PriceBreakdownCard(
                  pricePerKg: listing.pricePerKg,
                  quantityKg: _quantity,
                  distanceKm: listing.distanceKm,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isAddingToCart
                        ? null
                        : () => _addToCart(listing),
                    icon: _isAddingToCart
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.shopping_cart_outlined),
                    label: Text('add_to_cart'.tr()),
                  ),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 16),
        _Card(
          child: Column(
            children: [
              Row(
                children: [
                  AvatarImage(path: listing.farmerAvatarUrl, radius: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          listing.farmerName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (listing.distanceKm != null)
                          Text(
                            '${listing.distanceKm!.toStringAsFixed(1)} km ${'away'.tr()}',
                            style: theme.textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _messageFarmer,
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: Text('message_farmer'.tr()),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

class _OfflineBanner extends StatelessWidget {
  final ThemeData theme;

  const _OfflineBanner({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 18,
            color: theme.colorScheme.onTertiaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              // The marketplace is server-backed, so offline means this
              // data may be stale — not that edits will sync later.
              'offline_listing_may_be_stale'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onTertiaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodySmall),
                Text(
                  value,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;

  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: child,
    );
  }
}

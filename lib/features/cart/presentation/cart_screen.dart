import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../core/widgets/app_header.dart';
import '../../../core/widgets/media_image.dart';
import '../../../models/cart_item.dart';
import '../../../models/marketplace_listing.dart';
import '../../../models/profile.dart';
import '../../marketplace/marketplace_service.dart';
import '../../orders/presentation/checkout_screen.dart';
import '../cart_service.dart';

/// Sprint 2 — Task 3.1: Cart Management (buyer "Cart" tab).
///
/// Reads/writes are entirely local (see [CartService]) — the cart works
/// offline. Farmer display names/avatars are the one thing that isn't
/// in the local mirror (buyers only sync their own `profile` row under
/// RLS), so those are enriched best-effort via [MarketplaceService] per
/// unique listing and simply fall back to a generic label if offline.
class CartScreen extends StatefulWidget {
  final Profile profile;

  const CartScreen({super.key, required this.profile});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final _cartService = const CartService();
  final _marketplaceService = const MarketplaceService();

  StreamSubscription<List<CartLineItem>>? _sub;
  List<CartLineItem> _items = [];
  bool _isLoading = true;

  /// produceListingId -> enrichment fetched from the marketplace RPC.
  final Map<String, MarketplaceListing> _enrichment = {};
  final Set<String> _pendingRemovals = {};

  String get _buyerProfileId => widget.profile.id;

  @override
  void initState() {
    super.initState();
    _sub = _cartService.watchCartItems(_buyerProfileId).listen((items) {
      if (!mounted) return;
      setState(() {
        _items = items;
        _isLoading = false;
      });
      _enrichMissing(items);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  /// Fetches farmer name/avatar for any listing in the cart that isn't
  /// already cached. Best-effort: failures (e.g. offline) just mean the
  /// group header falls back to a generic label — the cart itself still
  /// works fully from local data.
  Future<void> _enrichMissing(List<CartLineItem> items) async {
    final missingIds = items
        .map((item) => item.produceListingId)
        .toSet()
        .where((id) => !_enrichment.containsKey(id));

    for (final id in missingIds) {
      try {
        final listing = await _marketplaceService.getListing(id);
        if (!mounted) return;
        if (listing != null) {
          setState(() => _enrichment[id] = listing);
        }
      } catch (_) {
        // Offline or transient — leave the fallback label in place.
      }
    }
  }

  List<CartFarmerGroup> get _groups {
    final byFarmer = <String, List<CartLineItem>>{};
    for (final item in _items) {
      byFarmer.putIfAbsent(item.farmerProfileId, () => []).add(item);
    }
    return byFarmer.entries
        .map((e) => CartFarmerGroup(farmerProfileId: e.key, items: e.value))
        .toList();
  }

  double get _grandTotal => _items.fold(0, (sum, item) => sum + item.lineTotal);

  Future<void> _changeQuantity(CartLineItem item, double newQty) async {
    // Optimistic local update happens naturally via the watch stream,
    // but guard against double-taps racing the same row.
    if (_pendingRemovals.contains(item.cartItemId)) return;
    await _cartService.updateQuantity(item.cartItemId, newQty);
  }

  Future<void> _removeItem(CartLineItem item) async {
    setState(() => _pendingRemovals.add(item.cartItemId));
    await _cartService.removeItem(item.cartItemId);
    if (!mounted) return;
    setState(() => _pendingRemovals.remove(item.cartItemId));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppHeader(profile: widget.profile),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                ? _EmptyCart(profile: widget.profile)
                : _buildCartContent(context),
          ),
        ),
      ),
    );
  }

  Widget _buildCartContent(BuildContext context) {
    final theme = Theme.of(context);
    final groups = _groups;

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            itemCount: groups.length,
            itemBuilder: (context, index) {
              final group = groups[index];
              final enrichment =
                  _enrichment[group.items.first.produceListingId];
              return _FarmerGroupCard(
                group: group,
                farmerName: enrichment?.farmerName,
                farmerAvatarUrl: enrichment?.farmerAvatarUrl,
                pendingRemovals: _pendingRemovals,
                enrichmentMap: _enrichment,
                onChangeQuantity: _changeQuantity,
                onRemove: _removeItem,
              );
            },
          ),
        ),
        _CartSummaryBar(
          grandTotal: _grandTotal,
          hasUnavailableItems: _items.any((item) => item.isUnavailable),
          onCheckout: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CheckoutScreen(buyerProfile: widget.profile),
            ),
          ),
          theme: theme,
        ),
      ],
    );
  }
}

class _EmptyCart extends StatelessWidget {
  final Profile profile;

  const _EmptyCart({required this.profile});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.shopping_cart_outlined,
            size: 56,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'cart_empty_title'.tr(),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'cart_empty_subtitle'.tr(),
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

class _FarmerGroupCard extends StatelessWidget {
  final CartFarmerGroup group;
  final String? farmerName;
  final String? farmerAvatarUrl;
  final Set<String> pendingRemovals;
  final void Function(CartLineItem item, double newQty) onChangeQuantity;
  final void Function(CartLineItem item) onRemove;
  final Map<String, MarketplaceListing> enrichmentMap;

  const _FarmerGroupCard({
    required this.group,
    required this.pendingRemovals,
    required this.onChangeQuantity,
    required this.onRemove,
    required this.enrichmentMap,
    this.farmerName,
    this.farmerAvatarUrl,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Icon(
                  Icons.storefront_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    farmerName ?? 'unknown_farmer'.tr(),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (group.hasUnavailableItems)
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 18,
                    color: theme.colorScheme.error,
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          for (final item in group.items)
            _CartItemTile(
              item: item,
              enrichedImageUrl: enrichmentMap[item.produceListingId]?.imageUrl,
              isRemoving: pendingRemovals.contains(item.cartItemId),
              onChangeQuantity: (qty) => onChangeQuantity(item, qty),
              onRemove: () => onRemove(item),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('farmer_subtotal'.tr(), style: theme.textTheme.bodyMedium),
                Text(
                  '${'currency_prefix'.tr()} ${group.subtotal.toStringAsFixed(2)}',
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

class _CartItemTile extends StatelessWidget {
  final CartLineItem item;
  final String? enrichedImageUrl;
  final bool isRemoving;
  final ValueChanged<double> onChangeQuantity;
  final VoidCallback onRemove;

  const _CartItemTile({
    required this.item,
    this.enrichedImageUrl,
    required this.isRemoving,
    required this.onChangeQuantity,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Opacity(
      opacity: isRemoving ? 0.4 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 56,
                height: 56,
                child: MediaImage(
                  path: enrichedImageUrl ?? item.imageUrl,

                  bucket: 'crop-photos',
                  placeholder: Container(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: Icon(
                      Icons.image_outlined,
                      size: 22,
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
                    item.cropName,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${'currency_prefix'.tr()} ${item.pricePerKg.toStringAsFixed(2)} '
                    '${'per_kg'.tr()}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (item.isUnavailable) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.availableQuantityKg <= 0
                          ? 'cart_item_sold_out'.tr()
                          : 'cart_item_unavailable'.tr(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ] else if (item.exceedsStock) ...[
                    const SizedBox(height: 4),
                    Text(
                      'cart_item_only_x_left'.tr(
                        namedArgs: {
                          'qty': item.availableQuantityKg.toStringAsFixed(0),
                        },
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _QuantityStepper(
                        quantity: item.quantityKg,
                        maxQuantity: item.availableQuantityKg,
                        enabled: !isRemoving && !item.isUnavailable,
                        onChanged: onChangeQuantity,
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: isRemoving ? null : onRemove,
                        icon: const Icon(Icons.delete_outline),
                        color: theme.colorScheme.onSurfaceVariant,
                        tooltip: 'remove_from_cart'.tr(),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${'currency_prefix'.tr()} ${item.lineTotal.toStringAsFixed(2)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuantityStepper extends StatelessWidget {
  final double quantity;
  final double maxQuantity;
  final bool enabled;
  final ValueChanged<double> onChanged;

  const _QuantityStepper({
    required this.quantity,
    required this.maxQuantity,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepperButton(
            icon: Icons.remove,
            onPressed: enabled && quantity > 1
                ? () =>
                      onChanged((quantity - 1).clamp(0, maxQuantity).toDouble())
                : null,
          ),
          SizedBox(
            width: 32,
            child: Text(
              quantity.toStringAsFixed(0),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          _StepperButton(
            icon: Icons.add,
            onPressed: enabled && quantity < maxQuantity
                ? () =>
                      onChanged((quantity + 1).clamp(0, maxQuantity).toDouble())
                : null,
          ),
        ],
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;

  const _StepperButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      customBorder: const CircleBorder(),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(
          icon,
          size: 16,
          color: onPressed == null
              ? Theme.of(context).colorScheme.outline
              : Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _CartSummaryBar extends StatelessWidget {
  final double grandTotal;
  final bool hasUnavailableItems;
  final VoidCallback onCheckout;
  final ThemeData theme;

  const _CartSummaryBar({
    required this.grandTotal,
    required this.hasUnavailableItems,
    required this.onCheckout,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasUnavailableItems) ...[
              Text(
                'cart_has_unavailable_items'.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
              const SizedBox(height: 8),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'grand_total'.tr(),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${'currency_prefix'.tr()} ${grandTotal.toStringAsFixed(2)}',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: onCheckout,
              child: Text('proceed_to_checkout'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}

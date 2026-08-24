import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../core/widgets/media_image.dart';
import '../../../models/cart_item.dart';
import '../../../models/marketplace_listing.dart';
import '../../../models/profile.dart';
import '../../cart/cart_service.dart';
import '../../marketplace/marketplace_service.dart';
import '../checkout_service.dart';
import '../order_models.dart';
import 'order_confirmation_screen.dart';

enum _PaymentMethod { wallet, card }

/// Sprint 2 — Task 3.2: Checkout screen.
///
/// Reads the live cart (same [CartService] stream the cart screen
/// uses), groups it by farmer, and shows one price breakdown per
/// farmer plus a grand total — since a multi-farmer cart becomes one
/// `orders` row per farmer at [CheckoutService.placeOrder] time. See
/// that service for why there's no separate `sub_orders` table.
class CheckoutScreen extends StatefulWidget {
  final Profile buyerProfile;

  const CheckoutScreen({super.key, required this.buyerProfile});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _cartService = const CartService();
  final _marketplaceService = const MarketplaceService();
  final _checkoutService = const CheckoutService();

  StreamSubscription<List<CartLineItem>>? _sub;
  List<CartLineItem> _items = [];
  bool _isLoading = true;
  bool _isPlacingOrder = false;
  String? _errorMessage;
  _PaymentMethod _paymentMethod = _PaymentMethod.wallet;

  /// produceListingId -> enrichment, same best-effort pattern as the
  /// cart screen — only used here to label each group with a farmer
  /// name instead of a raw id.
  final Map<String, MarketplaceListing> _enrichment = {};

  String get _buyerProfileId => widget.buyerProfile.id;

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
        // Offline or transient — group header falls back to a generic
        // label, same as the cart screen.
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

  bool get _hasUnavailableItems => _items.any((item) => item.isUnavailable);

  Future<void> _placeOrder() async {
    if (_items.isEmpty || _hasUnavailableItems || _isPlacingOrder) return;

    if (widget.buyerProfile.address.isEmpty) {
      setState(() => _errorMessage = 'checkout_no_address'.tr());
      return;
    }

    setState(() {
      _isPlacingOrder = true;
      _errorMessage = null;
    });

    try {
      final placedGroup = await _checkoutService.placeOrder(
        buyerProfile: widget.buyerProfile,
        items: _items,
        paymentMethod: _paymentMethod.name,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => OrderConfirmationScreen(
            buyerProfile: widget.buyerProfile,
            placedOrderGroup: placedGroup,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isPlacingOrder = false;
        _errorMessage = 'checkout_failed'.tr();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('checkout_title'.tr()),
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
                : _buildContent(context),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final theme = Theme.of(context);
    final summary = _checkoutService.buildSummary(_items);
    final groups = _groups;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            children: [
              _DeliveryDetailsCard(profile: widget.buyerProfile),
              const SizedBox(height: 16),
              _SectionHeader(title: 'order_summary'.tr()),
              const SizedBox(height: 8),
              ...groups.map((group) {
                final enrichment =
                    _enrichment[group.items.first.produceListingId];
                return _FarmerOrderCard(
                  group: group,
                  farmerName: enrichment?.farmerName,
                  farmerAvatarUrl: enrichment?.farmerAvatarUrl,
                );
              }),
              const SizedBox(height: 16),
              _SectionHeader(title: 'payment_method'.tr()),
              const SizedBox(height: 8),
              _PaymentMethodSelector(
                selected: _paymentMethod,
                onChanged: (method) => setState(() => _paymentMethod = method),
              ),
              const SizedBox(height: 16),
              _PriceBreakdownCard(summary: summary),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
        _PlaceOrderBar(
          enabled:
              _items.isNotEmpty && !_hasUnavailableItems && !_isPlacingOrder,
          isLoading: _isPlacingOrder,
          onPressed: _placeOrder,
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium
          ?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

class _DeliveryDetailsCard extends StatelessWidget {
  final Profile profile;

  const _DeliveryDetailsCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final address = profile.address;

    return Container(
      padding: const EdgeInsets.all(14),
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
              Icon(
                Icons.location_on_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'delivery_details'.tr(),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('edit_address_coming_soon'.tr())),
                ),
                child: Text('edit'.tr()),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${profile.firstName} ${profile.lastName}',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (!address.isEmpty)
            Text(
              address.formatted,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          if (profile.phone != null && profile.phone!.isNotEmpty)
            Text(
              profile.phone!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

class _FarmerOrderCard extends StatelessWidget {
  final CartFarmerGroup group;
  final String? farmerName;
  final String? farmerAvatarUrl;

  const _FarmerOrderCard({
    required this.group,
    this.farmerName,
    this.farmerAvatarUrl,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: Row(
              children: [
                Icon(
                  Icons.storefront_outlined,
                  size: 16,
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
              ],
            ),
          ),
          ...group.items.map(
            (item) => Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: MediaImage(
                        path: item.imageUrl,
                        bucket: 'crop-photos',
                        placeholder: Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: Icon(
                            Icons.image_outlined,
                            size: 18,
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.cropName,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${item.quantityKg} kg',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    item.lineTotal.toStringAsFixed(2),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'farmer_subtotal'.tr(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  group.subtotal.toStringAsFixed(2),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
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

class _PaymentMethodSelector extends StatelessWidget {
  final _PaymentMethod selected;
  final ValueChanged<_PaymentMethod> onChanged;

  const _PaymentMethodSelector({
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _PaymentOptionTile(
          icon: Icons.account_balance_wallet_outlined,
          label: 'greenyield_wallet'.tr(),
          selected: selected == _PaymentMethod.wallet,
          onTap: () => onChanged(_PaymentMethod.wallet),
        ),
        const SizedBox(height: 8),
        _PaymentOptionTile(
          icon: Icons.credit_card_outlined,
          label: 'card_payment'.tr(),
          selected: selected == _PaymentMethod.card,
          onTap: () => onChanged(_PaymentMethod.card),
        ),
      ],
    );
  }
}

class _PaymentOptionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PaymentOptionTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
              : theme.colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline,
            ),
          ],
        ),
      ),
    );
  }
}

class _PriceBreakdownCard extends StatelessWidget {
  final CheckoutSummary summary;

  const _PriceBreakdownCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget row(String label, double value, {bool bold = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style:
                  (bold
                          ? theme.textTheme.titleSmall
                          : theme.textTheme.bodyMedium)
                      ?.copyWith(
                        fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
                        color: bold ? null : theme.colorScheme.onSurfaceVariant,
                      ),
            ),
            Text(
              value.toStringAsFixed(2),
              style:
                  (bold
                          ? theme.textTheme.titleSmall
                          : theme.textTheme.bodyMedium)
                      ?.copyWith(
                        fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
                      ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          row('subtotal'.tr(), summary.subtotal),
          row('delivery_fee'.tr(), summary.deliveryFee),
          row('tax'.tr(), summary.tax),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Divider(height: 1),
          ),
          row('total'.tr(), summary.total, bold: true),
        ],
      ),
    );
  }
}

class _PlaceOrderBar extends StatelessWidget {
  final bool enabled;
  final bool isLoading;
  final VoidCallback onPressed;

  const _PlaceOrderBar({
    required this.enabled,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton.icon(
            onPressed: enabled ? onPressed : null,
            icon: isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_circle_outline),
            label: Text(isLoading ? 'placing_order'.tr() : 'place_order'.tr()),
          ),
        ),
      ),
    );
  }
}

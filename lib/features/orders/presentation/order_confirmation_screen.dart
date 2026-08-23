import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/widgets/media_image.dart';
import '../../../models/profile.dart';
import '../order_models.dart';

/// Sprint 2 — Task 3.2: Order Confirmation screen, shown right after
/// [CheckoutScreen] finishes writing every per-farmer `orders` row
/// locally via `CheckoutService.placeOrder`.
///
/// A multi-farmer checkout produces several `orders` rows sharing one
/// `checkout_group_id` (see `CheckoutService`) — this screen presents
/// that whole group as a single confirmed "order" the way the buyer
/// experiences it, while [PlacedOrderGroup.farmerCount] quietly notes
/// how many farmers it was actually split across underneath.
class OrderConfirmationScreen extends StatefulWidget {
  final Profile buyerProfile;
  final PlacedOrderGroup placedOrderGroup;

  const OrderConfirmationScreen({
    super.key,
    required this.buyerProfile,
    required this.placedOrderGroup,
  });

  @override
  State<OrderConfirmationScreen> createState() =>
      _OrderConfirmationScreenState();
}

class _OrderConfirmationScreenState extends State<OrderConfirmationScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _scale = CurvedAnimation(parent: _controller, curve: Curves.elasticOut);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _deliveryWindowText {
    // Hardcoded next-day window for Sprint 2 — real delivery-slot
    // estimation is a later sprint (depends on driver assignment).
    return 'delivery_window'.tr();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final group = widget.placedOrderGroup;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 32, 20, 20),
              children: [
                Center(
                  child: ScaleTransition(
                    scale: _scale,
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.colorScheme.primaryContainer.withValues(
                          alpha: 0.5,
                        ),
                      ),
                      child: Icon(
                        Icons.check_circle,
                        size: 56,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'order_confirmed'.tr(),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'order_confirmed_subtitle'.tr(),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (group.farmerCount > 1) ...[
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      'orders_placed_count'.tr(
                        namedArgs: {'count': '${group.farmerCount}'},
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                ...List.generate(
                  group.summary.subOrders.length,
                  (index) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _OrderSummaryCard(
                      orderId: group.orderIds[index],
                      summary: group.summary.subOrders[index],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.local_shipping_outlined,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'expected_delivery'.tr(),
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(_deliveryWindowText),
                            if (!group.deliveryAddress.isEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                'delivered_to'.tr(
                                  namedArgs: {
                                    'address': group.deliveryAddress.formatted,
                                  },
                                ),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('track_order_coming_soon'.tr())),
                    ),
                    icon: const Icon(Icons.track_changes_outlined),
                    label: Text('track_order'.tr()),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton(
                    onPressed: () =>
                        Navigator.of(context)
                            .popUntil((route) => route.isFirst),
                    child: Text('return_to_marketplace'.tr()),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OrderSummaryCard extends StatelessWidget {
  final String orderId;
  final CheckoutSubOrder summary;

  const _OrderSummaryCard({required this.orderId, required this.summary});

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'order_summary'.tr(),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: orderId));
              if (!context.mounted) return;
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('order_id_copied'.tr())));
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'order_number'.tr(
                      namedArgs: {'id': _shortOrderId(orderId)},
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.copy_outlined,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          ...summary.items.map(
            (item) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: MediaImage(
                        path: item.imageUrl,
                        bucket: 'crop-photos',
                        placeholder: Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: Icon(
                            Icons.image_outlined,
                            size: 20,
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${item.cropName}  ·  ${item.quantityKg} kg',
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  Text(item.lineTotal.toStringAsFixed(2)),
                ],
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Divider(height: 1),
          ),
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

String _shortOrderId(String orderId) {
  final compactId = orderId.replaceAll('-', '');
  return 'GY-${compactId.substring(0, 6).toUpperCase()}';
}

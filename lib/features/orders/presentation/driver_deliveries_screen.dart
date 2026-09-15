import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_secondary_header.dart';
import '../../../core/widgets/media_image.dart';
import '../../../models/profile.dart';
import '../order_providers.dart';
import '../order_detail_models.dart';
import 'order_detail_screen.dart';
import 'widgets/order_status_chip.dart';

/// Sprint 3 — Driver: 3-tab Deliveries screen.
/// Tab 1: Pickup Requests (assigned, packed)
/// Tab 2: Active Deliveries (picked_up, in_transit)
/// Tab 3: Completed (delivered)
class DriverDeliveriesScreen extends ConsumerStatefulWidget {
  final Profile profile;

  const DriverDeliveriesScreen({super.key, required this.profile});

  @override
  ConsumerState<DriverDeliveriesScreen> createState() =>
      _DriverDeliveriesScreenState();
}

class _DriverDeliveriesScreenState extends ConsumerState<DriverDeliveriesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profileId = widget.profile.id;

    return Scaffold(
      appBar: AppSecondaryHeader(
        title: 'Deliveries',
        showBackButton: false,
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Pickup Requests'),
            Tab(text: 'Active Deliveries'),
            Tab(text: 'Completed'),
          ],
          labelStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: const TextStyle(fontSize: 13),
          indicatorSize: TabBarIndicatorSize.tab,
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _DeliveryList(
            key: const ValueKey('driver_pickup'),
            provider: ref.watch(driverPickupRequestsProvider(profileId)),
            emptyMessage: 'No pickup requests right now.',
            emptyIcon: Icons.storefront_outlined,
          ),
          _DeliveryList(
            key: const ValueKey('driver_active'),
            provider: ref.watch(driverActiveDeliveriesProvider(profileId)),
            emptyMessage: 'No active deliveries in transit.',
            emptyIcon: Icons.local_shipping_outlined,
          ),
          _DeliveryList(
            key: const ValueKey('driver_completed'),
            provider: ref.watch(driverCompletedDeliveriesProvider(profileId)),
            emptyMessage: 'No completed deliveries yet.',
            emptyIcon: Icons.task_alt_outlined,
          ),
        ],
      ),
    );
  }
}

class _DeliveryList extends ConsumerWidget {
  final AsyncValue<List<DeliverySummary>> provider;
  final String emptyMessage;
  final IconData emptyIcon;

  const _DeliveryList({
    super.key,
    required this.provider,
    required this.emptyMessage,
    required this.emptyIcon,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return provider.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text(
          'Error loading deliveries:\n$e',
          textAlign: TextAlign.center,
        ),
      ),
      data: (deliveries) {
        if (deliveries.isEmpty) {
          final theme = Theme.of(context);
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    emptyIcon,
                    size: 52,
                    color: theme.colorScheme.outlineVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    emptyMessage,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: deliveries.length,
          itemBuilder: (context, i) => _DeliveryTile(delivery: deliveries[i]),
        );
      },
    );
  }
}

class _DeliveryTile extends StatelessWidget {
  final DeliverySummary delivery;

  const _DeliveryTile({required this.delivery});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final order = delivery.order;

    final cropLabel = order.cropNames.isNotEmpty
        ? order.cropNames.join(', ')
        : 'Order';

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              OrderDetailScreen(orderId: order.id, viewerRole: 'driver'),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  order.displayId,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                OrderStatusChip(status: order.status),
              ],
            ),
            const SizedBox(height: 12),

            // Pickup to dropoff visual
            Row(
              children: [
                // Dots and line
                Column(
                  children: [
                    Icon(
                      Icons.storefront,
                      size: 14,
                      color: theme.colorScheme.primary,
                    ),
                    Container(
                      width: 2,
                      height: 16,
                      color: theme.colorScheme.outlineVariant,
                    ),
                    Icon(
                      Icons.location_on,
                      size: 14,
                      color: theme.colorScheme.error,
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        delivery.farmerDisplayName ?? 'Farmer',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        delivery.buyerDisplayName ?? 'Buyer',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),
            Divider(color: theme.colorScheme.outlineVariant),
            const SizedBox(height: 6),

            Row(
              children: [
                if (order.firstImageUrl != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: MediaImage(
                        path: order.firstImageUrl!,
                        bucket: 'crop-photos',
                        placeholder: Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: Icon(
                            Icons.image_outlined,
                            size: 12,
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ] else ...[
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    cropLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

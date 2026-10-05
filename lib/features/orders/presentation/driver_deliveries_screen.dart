import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_header.dart';
import '../../../core/widgets/media_image.dart';
import '../../../models/profile.dart';
import '../order_detail_models.dart';
import '../order_providers.dart';
import 'order_detail_screen.dart';
import 'widgets/order_status_chip.dart';

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
    _tabs = TabController(length: 2, vsync: this);
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
      appBar: AppHeader(profile: widget.profile),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Container(
              height: 44,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Theme.of(context).colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.5)
                    : const Color(0xFFE8F0EA),
                borderRadius: BorderRadius.circular(24),
              ),
              child: TabBar(
                controller: _tabs,
                tabs: [
                  Tab(text: 'tab_pickup_requests'.tr()),
                  Tab(text: 'tab_completed'.tr()),
                ],
                labelColor: Theme.of(context).colorScheme.primary,
                unselectedLabelColor: Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant,
                labelStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                indicator: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Theme.of(context).colorScheme.primary
                            .withValues(alpha: 0.25)
                      : const Color(0xFFD3E8D7),
                  borderRadius: BorderRadius.circular(20),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                overlayColor: WidgetStateProperty.all(Colors.transparent),
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _DeliveryList(
                  key: const ValueKey('driver_pickup'),
                  provider: ref.watch(driverPickupRequestsProvider(profileId)),
                  emptyMessage: 'empty_pickup_requests'.tr(),
                  emptyIcon: Icons.storefront_outlined,
                  isHistory: false,
                ),
                _DeliveryList(
                  key: const ValueKey('driver_completed'),
                  provider: ref.watch(
                    driverCompletedDeliveriesProvider(profileId),
                  ),
                  emptyMessage: 'empty_completed'.tr(),
                  emptyIcon: Icons.task_alt_outlined,
                  isHistory: true,
                ),
              ],
            ),
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
  final bool isHistory;

  const _DeliveryList({
    super.key,
    required this.provider,
    required this.emptyMessage,
    required this.emptyIcon,
    required this.isHistory,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return provider.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text(
          'error_loading_deliveries'.tr(namedArgs: {'error': '$e'}),
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
        return _GroupedDeliveryList(
          deliveries: deliveries,
          isHistory: isHistory,
        );
      },
    );
  }
}

class _GroupedDeliveryList extends StatelessWidget {
  final List<DeliverySummary> deliveries;
  final bool isHistory;

  const _GroupedDeliveryList({
    required this.deliveries,
    required this.isHistory,
  });

  @override
  Widget build(BuildContext context) {
    final grouped = <DateTime, List<DeliverySummary>>{};
    for (final delivery in deliveries) {
      final sourceDate = isHistory
          ? (delivery.deliveredAt ?? delivery.order.placedAt)
          : delivery.order.orderDate ?? delivery.order.placedAt;
      final date = DateTime(sourceDate.year, sourceDate.month, sourceDate.day);
      grouped.putIfAbsent(date, () => []).add(delivery);
    }
    final dates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    final itemCount = dates.fold<int>(
      0,
      (count, date) => count + 1 + grouped[date]!.length,
    );

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        var offset = 0;
        for (final date in dates) {
          if (index == offset) {
            return Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 8),
              child: Text(
                DateFormat('MMM d, yyyy').format(date),
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            );
          }
          offset++;
          final dateDeliveries = grouped[date]!;
          if (index < offset + dateDeliveries.length) {
            return _DeliveryTile(delivery: dateDeliveries[index - offset]);
          }
          offset += dateDeliveries.length;
        }
        return const SizedBox.shrink();
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
    final imageBucket = _imageBucket(order.firstImageUrl);

    void openDetails() {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              OrderDetailScreen(orderId: order.id, viewerRole: 'driver'),
        ),
      );
    }

    return GestureDetector(
      onTap: openDetails,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        child: Card(
          margin: EdgeInsets.zero,
          elevation: 0,
          color: theme.colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: theme.shadowColor.withValues(alpha: 0.05),
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
                _RouteFlow(
                  farmerName: delivery.farmerDisplayName ?? 'Farmer',
                  buyerName: delivery.buyerDisplayName ?? 'Buyer',
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.brightness == Brightness.dark
                        ? theme.colorScheme.surfaceContainerHighest.withValues(
                            alpha: 0.35,
                          )
                        : const Color(0xFFF5F7F6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          width: 50,
                          height: 50,
                          child:
                              order.firstImageUrl != null &&
                                  order.firstImageUrl!.isNotEmpty
                              ? MediaImage(
                                  path: order.firstImageUrl!,
                                  bucket: imageBucket,
                                  public: imageBucket == 'crop-fallback-images',
                                  fit: BoxFit.cover,
                                  placeholder: _fallbackImage(theme),
                                )
                              : _fallbackImage(theme),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          cropLabel,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${order.totalQuantity.toStringAsFixed(0)} kg',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _fallbackImage(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.eco_outlined,
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
      ),
    );
  }

  String _imageBucket(String? path) {
    if (path == null) return 'crop-photos';
    if (path.contains('crop-fallback') ||
        path.startsWith('crops/') ||
        !path.contains('/')) {
      return 'crop-fallback-images';
    }
    return 'crop-photos';
  }
}

class _RouteFlow extends StatelessWidget {
  final String farmerName;
  final String buyerName;

  const _RouteFlow({required this.farmerName, required this.buyerName});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35)
            : const Color(0xFFF5F7F6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: _RoutePoint(
              icon: Icons.storefront_outlined,
              color: theme.colorScheme.primary,
              label: 'Pickup',
              name: farmerName,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Icon(
              Icons.east_rounded,
              size: 24,
              color: theme.colorScheme.primary.withValues(alpha: 0.7),
            ),
          ),
          Expanded(
            child: _RoutePoint(
              icon: Icons.location_on_outlined,
              color: theme.colorScheme.error,
              label: 'Drop-off',
              name: buyerName,
              alignEnd: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoutePoint extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String name;
  final bool alignEnd;

  const _RoutePoint({
    required this.icon,
    required this.color,
    required this.label,
    required this.name,
    this.alignEnd = false,
  });

  @override
  Widget build(BuildContext context) {
    final textAlign = alignEnd ? TextAlign.end : TextAlign.start;
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: textAlign,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        Text(
          name,
          textAlign: textAlign,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

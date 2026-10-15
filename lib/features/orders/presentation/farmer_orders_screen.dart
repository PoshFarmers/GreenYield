import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/app_secondary_header.dart';
import '../../../models/profile.dart';
import '../order_providers.dart';
import '../order_detail_models.dart';
import 'widgets/order_summary_card.dart';

/// Sprint 3 — Farmer: 3-tab Orders screen.
/// Tab 1: To Pack (placed, confirmed, assigned)
/// Tab 2: Ready / In Transit (packed, picked_up, in_transit)
/// Tab 3: History (delivered, completed, cancelled)
class FarmerOrdersScreen extends ConsumerStatefulWidget {
  final Profile profile;

  const FarmerOrdersScreen({super.key, required this.profile});

  @override
  ConsumerState<FarmerOrdersScreen> createState() => _FarmerOrdersScreenState();
}

class _FarmerOrdersScreenState extends ConsumerState<FarmerOrdersScreen>
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
        title: 'Orders',
        showBackButton: false,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Container(
              height: 44,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F0EA),
                borderRadius: BorderRadius.circular(24),
              ),
              child: TabBar(
                controller: _tabs,
                tabs: const [
                  Tab(text: 'To Pack'),
                  Tab(text: 'Ready / In Transit'),
                  Tab(text: 'History'),
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
                  color: const Color(0xFFD3E8D7),
                  borderRadius: BorderRadius.circular(20),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                overlayColor: WidgetStateProperty.all(Colors.transparent),
              ),
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _OrderList(
            key: const ValueKey('farmer_to_pack'),
            provider: ref.watch(farmerToPackOrdersProvider(profileId)),
            viewerRole: 'farmer',
            isHistory: false,
            emptyMessage: 'No new orders to pack.',
            emptyIcon: Icons.inventory_2_outlined,
          ),
          _OrderList(
            key: const ValueKey('farmer_in_transit'),
            provider: ref.watch(farmerInTransitOrdersProvider(profileId)),
            viewerRole: 'farmer',
            isHistory: false,
            emptyMessage: 'No orders waiting for pickup or in transit.',
            emptyIcon: Icons.local_shipping_outlined,
          ),
          _OrderList(
            key: const ValueKey('farmer_history'),
            provider: ref.watch(farmerHistoryOrdersProvider(profileId)),
            viewerRole: 'farmer',
            isHistory: true,
            emptyMessage: 'No completed orders yet.',
            emptyIcon: Icons.history_outlined,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared list widget
// ---------------------------------------------------------------------------

class _OrderList extends ConsumerWidget {
  final AsyncValue<List<OrderSummary>> provider;
  final String viewerRole;
  final String emptyMessage;
  final IconData emptyIcon;
  final bool isHistory;

  const _OrderList({
    super.key,
    required this.provider,
    required this.viewerRole,
    required this.emptyMessage,
    required this.emptyIcon,
    required this.isHistory,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return provider.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text('Error loading orders:\n$e', textAlign: TextAlign.center),
      ),
      data: (orders) {
        if (orders.isEmpty) {
          final theme = Theme.of(context);
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    emptyIcon,
                    size: 64,
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
        final grouped = <DateTime, List<OrderSummary>>{};
        for (final order in orders) {
          final sourceDate = isHistory
              ? (order.deliveredAt ?? order.placedAt)
              : (order.orderDate ?? order.placedAt);
          final date = DateTime(
            sourceDate.year,
            sourceDate.month,
            sourceDate.day,
          );
          grouped.putIfAbsent(date, () => []).add(order);
        }
        final dates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
        final itemCount = dates.fold<int>(
          0,
          (count, date) => count + 1 + grouped[date]!.length,
        );

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
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
              final dateOrders = grouped[date]!;
              if (index < offset + dateOrders.length) {
                return OrderSummaryCard(
                  order: dateOrders[index - offset],
                  viewerRole: viewerRole,
                );
              }
              offset += dateOrders.length;
            }
            return const SizedBox.shrink();
          },
        );
      },
    );
  }
}

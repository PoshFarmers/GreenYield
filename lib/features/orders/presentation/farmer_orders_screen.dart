import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(text: 'To Pack'),
            Tab(text: 'Ready / In Transit'),
            Tab(text: 'History'),
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
          _OrderList(
            key: const ValueKey('farmer_to_pack'),
            provider: ref.watch(farmerToPackOrdersProvider(profileId)),
            viewerRole: 'farmer',
            emptyMessage: 'No new orders to pack.',
            emptyIcon: Icons.inventory_2_outlined,
          ),
          _OrderList(
            key: const ValueKey('farmer_in_transit'),
            provider: ref.watch(farmerInTransitOrdersProvider(profileId)),
            viewerRole: 'farmer',
            emptyMessage: 'No orders waiting for pickup or in transit.',
            emptyIcon: Icons.local_shipping_outlined,
          ),
          _OrderList(
            key: const ValueKey('farmer_history'),
            provider: ref.watch(farmerHistoryOrdersProvider(profileId)),
            viewerRole: 'farmer',
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

  const _OrderList({
    super.key,
    required this.provider,
    required this.viewerRole,
    required this.emptyMessage,
    required this.emptyIcon,
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
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          itemCount: orders.length,
          itemBuilder: (context, i) =>
              OrderSummaryCard(order: orders[i], viewerRole: viewerRole),
        );
      },
    );
  }
}

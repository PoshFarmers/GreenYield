import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_secondary_header.dart';
import '../../../models/profile.dart';
import '../order_providers.dart';
import '../order_detail_models.dart';
import 'widgets/order_summary_card.dart';

/// Sprint 3 — Buyer: 2-tab Orders screen.
/// Tab 1: Active Orders  (placed, confirmed, assigned, packed, picked_up, in_transit)
/// Tab 2: Order History  (delivered, completed, cancelled)
class BuyerOrdersScreen extends ConsumerStatefulWidget {
  final Profile profile;

  const BuyerOrdersScreen({super.key, required this.profile});

  @override
  ConsumerState<BuyerOrdersScreen> createState() => _BuyerOrdersScreenState();
}

class _BuyerOrdersScreenState extends ConsumerState<BuyerOrdersScreen>
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
      appBar: AppSecondaryHeader(
        title: 'My Orders',
        showBackButton: false,
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Active Orders'),
            Tab(text: 'Order History'),
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
            key: const ValueKey('buyer_active'),
            provider: ref.watch(buyerActiveOrdersProvider(profileId)),
            viewerRole: 'buyer',
            emptyMessage: 'No active orders yet.\nShop in the Marketplace to get started.',
            emptyIcon: Icons.shopping_bag_outlined,
          ),
          _OrderList(
            key: const ValueKey('buyer_history'),
            provider: ref.watch(buyerHistoryOrdersProvider(profileId)),
            viewerRole: 'buyer',
            emptyMessage: 'No order history yet.',
            emptyIcon: Icons.history_outlined,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared order list widget — used by Buyer screen
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
          return _EmptyState(message: emptyMessage, icon: emptyIcon);
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

class _EmptyState extends StatelessWidget {
  final String message;
  final IconData icon;

  const _EmptyState({required this.message, required this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: theme.colorScheme.outlineVariant),
            const SizedBox(height: 16),
            Text(
              message,
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
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_secondary_header.dart';
import '../../../models/buyer_profile.dart';
import '../../../models/profile.dart';
import '../../profile/buyer/buyer_profile_service.dart';
import '../order_providers.dart';
import '../order_detail_models.dart';
import 'widgets/order_summary_card.dart';
import 'recurring/recurring_schedule_list_screen.dart';

/// Buyer Orders screen.
///
/// Individual buyers  → 2 tabs: Active Orders | Order History
/// Org buyers         → 3 tabs: Active Orders | Scheduled Orders | Order History
class BuyerOrdersScreen extends ConsumerStatefulWidget {
  final Profile profile;

  const BuyerOrdersScreen({super.key, required this.profile});

  @override
  ConsumerState<BuyerOrdersScreen> createState() => _BuyerOrdersScreenState();
}

class _BuyerOrdersScreenState extends ConsumerState<BuyerOrdersScreen> {
  // Created once — previously a new stream was made on every build.
  late final Stream<BuyerProfile?> _buyerStream = BuyerProfileService()
      .watchOwnProfile(widget.profile.id)
      .asBroadcastStream();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<BuyerProfile?>(
      stream: _buyerStream,
      builder: (context, snap) {
        final isOrg = snap.data?.buyerType == 'organization';
        return _BuyerOrdersTabs(
          // A new TabController is only created when the tab count changes,
          // and never from inside a build (which caused setState-in-build).
          key: ValueKey(isOrg),
          profileId: widget.profile.id,
          isOrg: isOrg,
        );
      },
    );
  }
}

class _BuyerOrdersTabs extends ConsumerStatefulWidget {
  final String profileId;
  final bool isOrg;

  const _BuyerOrdersTabs({
    super.key,
    required this.profileId,
    required this.isOrg,
  });

  @override
  ConsumerState<_BuyerOrdersTabs> createState() => _BuyerOrdersTabsState();
}

class _BuyerOrdersTabsState extends ConsumerState<_BuyerOrdersTabs>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: widget.isOrg ? 3 : 2,
    vsync: this,
  );

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.profileId;
    final isOrg = widget.isOrg;

    return Scaffold(
      appBar: AppSecondaryHeader(
        title: 'Orders',
        showBackButton: false,
        bottom: TabBar(
          controller: _tabs,
          isScrollable: isOrg,
          tabs: [
            const Tab(text: 'Active Orders'),
            if (isOrg) const Tab(text: 'Scheduled'),
            const Tab(text: 'Order History'),
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
            provider: ref.watch(buyerActiveOrdersProvider(id)),
            viewerRole: 'buyer',
            emptyMessage: 'No active orders yet.\nShop in the Marketplace to get started.',
            emptyIcon: Icons.shopping_bag_outlined,
          ),
          if (isOrg) RecurringScheduleListWidget(buyerProfileId: id),
          _OrderList(
            key: const ValueKey('buyer_history'),
            provider: ref.watch(buyerHistoryOrdersProvider(id)),
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
// Shared order list widget
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
      skipLoadingOnReload: true,
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

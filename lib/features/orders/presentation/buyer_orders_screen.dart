import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

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
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: _OrderTabBar(
            controller: _tabs,
            tabs: [
              const Tab(text: 'Active Orders'),
              if (isOrg) const Tab(text: 'Scheduled'),
              const Tab(text: 'Order History'),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _OrderList(
            key: const ValueKey('buyer_active'),
            provider: ref.watch(buyerActiveOrdersProvider(id)),
            viewerRole: 'buyer',
            isHistory: false,
            emptyMessage: 'No active orders yet.\nShop in the Marketplace to get started.',
            emptyIcon: Icons.shopping_bag_outlined,
          ),
          if (isOrg) RecurringScheduleListWidget(buyerProfileId: id),
          _OrderList(
            key: const ValueKey('buyer_history'),
            provider: ref.watch(buyerHistoryOrdersProvider(id)),
            viewerRole: 'buyer',
            isHistory: true,
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
      skipLoadingOnReload: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text('Error loading orders:\n$e', textAlign: TextAlign.center),
      ),
      data: (orders) {
        if (orders.isEmpty) {
          return _EmptyState(message: emptyMessage, icon: emptyIcon);
        }
        final grouped = <DateTime, List<OrderSummary>>{};
        for (final order in orders) {
          final sourceDate = isHistory
              ? (order.deliveredAt ?? order.placedAt)
              : order.placedAt;
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

class _OrderTabBar extends StatelessWidget {
  final TabController controller;
  final List<Widget> tabs;

  const _OrderTabBar({required this.controller, required this.tabs});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Container(
        height: 44,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFE8F0EA),
          borderRadius: BorderRadius.circular(24),
        ),
        child: TabBar(
          controller: controller,
          tabs: tabs,
          labelColor: Theme.of(context).colorScheme.primary,
          unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
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

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../application/notification_providers.dart';
import 'widgets/notification_card.dart';

class NotificationScreen extends ConsumerStatefulWidget {
  const NotificationScreen({super.key});

  @override
  ConsumerState<NotificationScreen> createState() =>
      _NotificationScreenState();
}

class _NotificationScreenState extends ConsumerState<NotificationScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(notificationListProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationListProvider);
    final controller = ref.read(notificationListProvider.notifier);
    final unreadCount = ref.watch(unreadNotificationCountProvider).asData?.value ?? 0;

    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        title: Text('notifications_title'.tr()),
        actions: [
          TextButton(
            onPressed: unreadCount > 0 ? controller.markAllRead : null,
            child: Text('notifications_mark_all_read'.tr()),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final filter in NotificationFilter.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(_filterLabel(filter)),
                        selected: state.filter == filter,
                        selectedColor: AppColors.freshLeafGreen.withValues(
                          alpha: 0.25,
                        ),
                        onSelected: (_) => controller.setFilter(filter),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: controller.refresh,
              child: _buildBody(state, controller),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    NotificationListState state,
    NotificationListController controller,
  ) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null && state.items.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          const Icon(Icons.error_outline, size: 48, color: AppColors.mutedGray),
          const SizedBox(height: 12),
          Center(child: Text('notifications_load_error'.tr())),
        ],
      );
    }

    if (state.items.isEmpty) {
      return _EmptyState(onRefresh: controller.refresh);
    }

    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      itemCount: state.items.length + (state.hasMore ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index >= state.items.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final item = state.items[index];
        return Dismissible(
          key: ValueKey(item.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.delete_outline, color: Colors.white),
          ),
          onDismissed: (_) => controller.dismiss(item.id),
          child: NotificationCard(
            notification: item,
            onTap: () {
              if (!item.isRead) controller.markRead(item.id);
            },
          ),
        );
      },
    );
  }

  String _filterLabel(NotificationFilter filter) => switch (filter) {
    NotificationFilter.all => 'notifications_filter_all'.tr(),
    NotificationFilter.unread => 'notifications_filter_unread'.tr(),
    NotificationFilter.orders => 'notifications_filter_orders'.tr(),
    NotificationFilter.payments => 'notifications_filter_payments'.tr(),
    NotificationFilter.logistics => 'notifications_filter_logistics'.tr(),
    NotificationFilter.account => 'notifications_filter_account'.tr(),
  };
}

class _EmptyState extends StatelessWidget {
  final Future<void> Function() onRefresh;

  const _EmptyState({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 100),
        const Icon(
          Icons.notifications_none_rounded,
          size: 72,
          color: AppColors.mutedGray,
        ),
        const SizedBox(height: 16),
        Text(
          'notifications_empty_title'.tr(),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: AppColors.deepForestGreen,
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'notifications_empty_subtitle'.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.mutedGray),
          ),
        ),
      ],
    );
  }
}

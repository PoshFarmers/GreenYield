import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/notification_item.dart';
import 'notification_service.dart';

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(),
);

/// Live unread count for the global bell badge, synced offline via
/// PowerSync — updates instantly as rows sync in, get read, or deleted.
final unreadNotificationCountProvider = StreamProvider<int>((ref) {
  final service = ref.watch(notificationServiceProvider);
  return service.watchUnreadCount();
});

/// Filter chips shown above the notification list. Maps to a `type`
/// prefix, since the table has no separate category column.
enum NotificationFilter {
  all,
  unread,
  orders,
  payments,
  logistics,
  account;

  String? get typePrefix => switch (this) {
    NotificationFilter.orders => 'order_',
    NotificationFilter.payments => 'payment_',
    NotificationFilter.logistics => 'delivery_',
    NotificationFilter.account => 'role_',
    _ => null,
  };

  bool? get isRead => this == NotificationFilter.unread ? false : null;
}

class NotificationListState {
  final List<NotificationItem> items;
  final NotificationFilter filter;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final Object? error;

  const NotificationListState({
    this.items = const [],
    this.filter = NotificationFilter.all,
    this.isLoading = true,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
  });

  NotificationListState copyWith({
    List<NotificationItem>? items,
    NotificationFilter? filter,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    Object? error,
  }) {
    return NotificationListState(
      items: items ?? this.items,
      filter: filter ?? this.filter,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: error,
    );
  }
}

/// Drives NotificationScreen: paginated fetch (infinite scroll +
/// pull-to-refresh), filter chips, and optimistic mark-read/delete.
class NotificationListController extends Notifier<NotificationListState> {
  static const _pageSize = 20;

  late final NotificationService _service;

  @override
  NotificationListState build() {
    _service = ref.watch(notificationServiceProvider);
    _load(reset: true);
    return const NotificationListState();
  }

  Future<void> _load({required bool reset}) async {
    final currentFilter = state.filter;
    if (reset) {
      state = state.copyWith(isLoading: true, error: null);
    } else {
      if (!state.hasMore || state.isLoadingMore) return;
      state = state.copyWith(isLoadingMore: true);
    }

    try {
      final page = reset ? 0 : (state.items.length ~/ _pageSize);
      final results = await _service.fetchPage(
        isRead: currentFilter.isRead,
        typePrefix: currentFilter.typePrefix,
        page: page,
        limit: _pageSize,
      );

      final merged = reset ? results : [...state.items, ...results];
      state = state.copyWith(
        items: merged,
        isLoading: false,
        isLoadingMore: false,
        hasMore: results.length == _pageSize,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, isLoadingMore: false, error: e);
    }
  }

  Future<void> refresh() => _load(reset: true);

  Future<void> loadMore() => _load(reset: false);

  Future<void> setFilter(NotificationFilter filter) async {
    if (filter == state.filter) return;
    state = state.copyWith(filter: filter, items: [], hasMore: true);
    await _load(reset: true);
  }

  Future<void> markRead(String id) async {
    state = state.copyWith(
      items: [
        for (final n in state.items)
          if (n.id == id) n.copyWith(readAt: DateTime.now()) else n,
      ],
    );
    await _service.markRead(id);
  }

  Future<void> markAllRead() async {
    state = state.copyWith(
      items: [for (final n in state.items) n.copyWith(readAt: DateTime.now())],
    );
    await _service.markAllRead();
  }

  Future<void> dismiss(String id) async {
    final previous = state.items;
    state = state.copyWith(items: previous.where((n) => n.id != id).toList());
    try {
      await _service.delete(id);
    } catch (_) {
      // Restore on failure so the swiped card doesn't silently vanish.
      state = state.copyWith(items: previous);
    }
  }
}

final notificationListProvider =
    NotifierProvider<NotificationListController, NotificationListState>(
      NotificationListController.new,
    );

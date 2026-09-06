import '../../../core/local_db/powersync.dart';
import '../../../core/supabase/client.dart';
import '../../../models/notification_item.dart';

/// Reusable notification data-access layer, callable from anywhere in the
/// app. Reads/writes go through PowerSync's local SQLite (`db`) — like
/// every other feature in this app — rather than hitting Supabase
/// directly, since `notification` is on the PowerSync publication
/// (see `20260827094922_powersync_publication.sql`) and syncs offline
/// like the rest of the app's data. Notifications themselves are only
/// ever *inserted* by trusted backend code (the `send_notification()`
/// Postgres function and its triggers in
/// `20260829120000_notification_events.sql`) — this service only reads,
/// marks read, and deletes on behalf of the signed-in user.
class NotificationService {
  String? get _uid => supabase.auth.currentUser?.id;

  /// GET /api/notifications — paginated notifications for the signed-in
  /// user, optionally filtered by read state and/or a `type` prefix
  /// (e.g. 'order_' for the Orders filter chip).
  Future<List<NotificationItem>> fetchPage({
    bool? isRead,
    String? typePrefix,
    int page = 0,
    int limit = 20,
  }) async {
    final uid = _uid;
    if (uid == null) return [];

    final where = <String>['profile_id = ?', "type != 'new_message'"];
    final params = <Object?>[uid];

    if (isRead == true) where.add('read_at is not null');
    if (isRead == false) where.add('read_at is null');
    if (typePrefix != null) {
      where.add('type like ?');
      params.add('$typePrefix%');
    }

    params.addAll([limit, page * limit]);

    final rows = await db.getAll(
      'SELECT * FROM notification WHERE ${where.join(' AND ')} '
      'ORDER BY created_at DESC LIMIT ? OFFSET ?',
      params,
    );

    return rows.map(NotificationItem.fromMap).toList();
  }

  /// Live unread count for the app-wide badge — backed by PowerSync's
  /// watch stream, so it updates instantly as rows sync in or get read.
  Stream<int> watchUnreadCount() {
    final uid = _uid;
    if (uid == null) return Stream.value(0);
    return db
        .watch(
          "SELECT COUNT(*) as count FROM notification "
          "WHERE profile_id = ? AND read_at IS NULL AND type != 'new_message'",
          parameters: [uid],
        )
        .map((rows) => rows.first['count'] as int? ?? 0);
  }

  /// PATCH /api/notifications/:id/read
  Future<void> markRead(String id) async {
    await db.execute('UPDATE notification SET read_at = ? WHERE id = ?', [
      DateTime.now().toUtc().toIso8601String(),
      id,
    ]);
  }

  /// PATCH /api/notifications/read-all
  Future<void> markAllRead() async {
    final uid = _uid;
    if (uid == null) return;
    await db.execute(
      'UPDATE notification SET read_at = ? '
      'WHERE profile_id = ? AND read_at IS NULL',
      [DateTime.now().toUtc().toIso8601String(), uid],
    );
  }

  /// DELETE /api/notifications/:id
  Future<void> delete(String id) async {
    await db.execute('DELETE FROM notification WHERE id = ?', [id]);
  }
}

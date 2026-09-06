import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/supabase/client.dart';
import '../../models/chat_models.dart';

/// Messaging deliberately bypasses PowerSync entirely and talks to
/// Supabase directly — sub-second delivery needs live WebSocket
/// streams (`.stream()` / Realtime), not the offline-first mirror the
/// rest of the app reads from. Same reasoning as `MarketplaceService`:
/// this feature requires a live connection.
///
/// This sits on top of the existing `conversation` /
/// `conversation_participant` / `message` schema (extended in
/// 20260906000000_chat_system.sql) rather than a new one — see that
/// migration's header comment for why.
class ChatService {
  const ChatService();

  static const _attachmentsBucket = 'message-attachments';

  /// In-memory cache of resolved signed URLs so we don't re-sign the
  /// same path on every rebuild. Keys are storage paths; values are
  /// short-lived signed URLs valid for 1 hour within the session.
  static final Map<String, String> _urlCache = {};

  String get _uid {
    final id = supabase.auth.currentUser?.id;
    if (id == null) throw StateError('Not authenticated');
    return id;
  }

  /// Returns the id of the existing direct thread between the caller
  /// (acting as [callerRole]) and [otherUserId] (a [otherRole]), or
  /// creates one atomically via the `get_or_create_conversation` RPC.
  Future<String> getOrCreateConversation({
    required String callerRole,
    required String otherUserId,
    required String otherRole,
  }) async {
    final id = await supabase.rpc(
      'get_or_create_conversation',
      params: {
        'p_caller_role': callerRole,
        'p_other_user_id': otherUserId,
        'p_other_role': otherRole,
      },
    );
    return id as String;
  }

  /// One-shot fetch of every direct thread the caller is part of,
  /// newest first, with the other participant's display info, latest
  /// message snippet, and unread flag already resolved server-side.
  Future<List<ChatThread>> getChatThreads() async {
    final rows = await supabase.rpc('get_chat_threads');
    return (rows as List)
        .map((row) => ChatThread.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// Live thread list for `chat_threads_screen.dart`. Re-runs
  /// `get_chat_threads()` whenever any of the caller's conversations
  /// change — a new message bumps `conversation.updated_at` via a DB
  /// trigger, which is enough to re-derive snippets/unread/ordering
  /// without the client tracking any of that itself.
  ///
  /// A 300ms debounce prevents multiple rapid RPC calls when a burst
  /// of messages arrives at once.
  Stream<List<ChatThread>> watchChatThreads() {
    final controller = StreamController<List<ChatThread>>.broadcast();
    late final StreamSubscription<List<Map<String, dynamic>>> subscription;
    Timer? debounce;

    void refresh() {
      debounce?.cancel();
      debounce = Timer(const Duration(milliseconds: 300), () {
        getChatThreads()
            .then((threads) {
              if (!controller.isClosed) controller.add(threads);
            })
            .catchError((Object error) {
              if (!controller.isClosed) controller.addError(error);
            });
      });
    }

    controller.onListen = () {
      // Immediate first load — don't wait for the debounce.
      getChatThreads()
          .then((threads) {
            if (!controller.isClosed) controller.add(threads);
          })
          .catchError((Object error) {
            if (!controller.isClosed) controller.addError(error);
          });

      subscription = supabase
          .from('conversation')
          .stream(primaryKey: ['id'])
          .listen((_) => refresh());
    };
    controller.onCancel = () {
      debounce?.cancel();
      subscription.cancel();
    };

    return controller.stream;
  }

  /// Total number of *threads* (not messages) with at least one
  /// message newer than the caller's `last_read_at` cursor for that
  /// thread — feeds the yellow badge on every role's Chat nav tab.
  /// Re-derived via `unread_conversation_count()` whenever a message
  /// arrives, since the underlying comparison (created_at vs. a
  /// per-participant cursor) isn't something the client can cheaply
  /// recompute from raw stream rows alone.
  Stream<int> getUnreadConversationCountStream() {
    final controller = StreamController<int>.broadcast();
    late final StreamSubscription<List<Map<String, dynamic>>> subscription;

    void refresh() {
      supabase
          .rpc('unread_conversation_count')
          .then((value) {
            if (!controller.isClosed) controller.add(value as int);
          })
          .catchError((Object error) {
            if (!controller.isClosed) controller.addError(error);
          });
    }

    controller.onListen = () {
      refresh();
      subscription = supabase
          .from('message')
          .stream(primaryKey: ['id'])
          .listen((_) => refresh());
    };
    controller.onCancel = () => subscription.cancel();

    return controller.stream;
  }

  /// Sub-second live message stream for one conversation's room. RLS
  /// (`message_select_participant`) already keeps this scoped to
  /// conversations the caller belongs to.
  ///
  /// Ordered descending so newest message is at index 0 — matches the
  /// `reverse: true` ListView in `chat_screen.dart` which renders the
  /// list bottom-up (newest at bottom, oldest scrolled up to top).
  Stream<List<ChatMessage>> streamMessages(String conversationId) {
    return supabase
        .from('message')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: false)
        .map(
          (rows) => rows
              .map((row) => ChatMessage.fromMap(row))
              .toList(growable: false),
        );
  }

  /// Live `last_read_at` cursor for the OTHER participant in this
  /// conversation, so the room screen can render a "seen" checkmark
  /// on the caller's own messages (message.created_at <= this value).
  Stream<DateTime?> streamPeerLastReadAt(String conversationId) {
    return supabase
        .from('conversation_participant')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .map((rows) {
          final peer = rows.firstWhere(
            (row) => row['profile_id'] != _uid,
            orElse: () => const {},
          );
          final lastReadAt = peer['last_read_at'] as String?;
          return lastReadAt == null
              ? null
              : DateTime.parse(lastReadAt).toLocal();
        });
  }

  /// Sends a text message, an image, or both. [imageFile] is uploaded
  /// to the existing private `message-attachments` bucket first; only
  /// the storage *path* is persisted (not a public URL — the bucket
  /// isn't public), so the room screen resolves a short-lived signed
  /// URL to display it.
  Future<void> sendMessage({
    required String conversationId,
    String? text,
    File? imageFile,
  }) async {
    final trimmed = text?.trim();
    String? attachmentPath;
    String? attachmentType;

    if (imageFile != null) {
      final ext = imageFile.path.split('.').last.toLowerCase();
      attachmentPath = '$conversationId/${const Uuid().v4()}.$ext';
      await supabase.storage
          .from(_attachmentsBucket)
          .upload(
            attachmentPath,
            imageFile,
            fileOptions: FileOptions(contentType: 'image/$ext'),
          );
      attachmentType = 'image';
    }

    if ((trimmed == null || trimmed.isEmpty) && attachmentPath == null) {
      return; // nothing to send
    }

    await supabase.from('message').insert({
      'conversation_id': conversationId,
      'sender_id': _uid,
      'body': (trimmed == null || trimmed.isEmpty) ? null : trimmed,
      'attachment_url': attachmentPath,
      'attachment_type': attachmentType,
    });
  }

  /// Short-lived signed URL for an attachment path stored on a message.
  /// Results are cached in-memory for the session lifetime to avoid
  /// redundant signed-URL requests on every widget rebuild.
  Future<String> resolveAttachmentUrl(String path) {
    final cached = _urlCache[path];
    if (cached != null) return Future.value(cached);
    return supabase.storage
        .from(_attachmentsBucket)
        .createSignedUrl(path, 60 * 60) // 1 hour
        .then((url) {
          _urlCache[path] = url;
          return url;
        });
  }

  /// Advances the caller's own read cursor for this conversation to
  /// now. Covered by the existing `conversation_participant_update_own`
  /// RLS policy, so this is a plain table update rather than an RPC.
  Future<void> markMessagesAsRead(String conversationId) async {
    await supabase
        .from('conversation_participant')
        .update({'last_read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('conversation_id', conversationId)
        .eq('profile_id', _uid);
  }
}

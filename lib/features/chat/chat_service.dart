import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/supabase/client.dart';
import '../../models/chat_models.dart';

/// Direct messaging service.
///
/// Messaging intentionally uses Supabase Realtime instead of PowerSync.
/// Keep Realtime subscriptions scoped and avoid re-querying the same data
/// multiple times for one event.
class ChatService {
  const ChatService();

  static const _attachmentsBucket = 'message-attachments';

  /// Signed URLs are requested with a 1h lifetime; drop them from the cache a
  /// bit earlier so a long session never renders an expired URL.
  static const _urlTtl = Duration(minutes: 50);

  static final Map<String, ({String url, DateTime expiresAt})> _urlCache = {};

  String get _uid {
    final id = supabase.auth.currentUser?.id;
    if (id == null) throw StateError('Not authenticated');
    return id;
  }

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

  /// Fetches the current user's threads for the currently active role.
  ///
  /// The role is part of the participant snapshot in the database, so a user
  /// with several roles only sees threads belonging to the active one.
  Future<List<ChatThread>> getChatThreads(String activeRole) async {
    final rows = await supabase.rpc(
      'get_chat_threads',
      params: {'p_active_role': activeRole},
    );

    return (rows as List)
        .map((row) => ChatThread.fromMap(row as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// Live thread list.
  ///
  /// Two lightweight subscriptions:
  ///  - conversation: a message INSERT bumps conversation.updated_at
  ///  - participant: new conversations / read-cursor changes for this user
  ///
  /// A `.stream()` always emits an initial snapshot. We already call [load]
  /// when listening starts, so those snapshots are skipped; only real changes
  /// trigger a (debounced) refetch.
  Stream<List<ChatThread>> watchChatThreads(String activeRole) {
    final controller = StreamController<List<ChatThread>>.broadcast();

    StreamSubscription<List<Map<String, dynamic>>>? conversationSub;
    StreamSubscription<List<Map<String, dynamic>>>? participantSub;
    Timer? debounce;
    int requestVersion = 0;

    Future<void> load() async {
      final version = ++requestVersion;
      try {
        final threads = await getChatThreads(activeRole);
        // A slower, older RPC must never overwrite a newer result.
        if (!controller.isClosed && version == requestVersion) {
          controller.add(threads);
        }
      } catch (error, stackTrace) {
        if (!controller.isClosed && version == requestVersion) {
          controller.addError(error, stackTrace);
        }
      }
    }

    void scheduleRefresh() {
      debounce?.cancel();
      debounce = Timer(const Duration(milliseconds: 200), load);
    }

    controller.onListen = () {
      load();

      conversationSub = supabase
          .from('conversation')
          .stream(primaryKey: ['id'])
          .skip(1)
          .listen((_) => scheduleRefresh());

      participantSub = supabase
          .from('conversation_participant')
          .stream(primaryKey: ['id'])
          .eq('profile_id', _uid)
          .skip(1)
          .listen((_) => scheduleRefresh());
    };

    controller.onCancel = () {
      debounce?.cancel();
      // Invalidate in-flight loads so an old result cannot be emitted after
      // the provider has been disposed.
      requestVersion++;
      conversationSub?.cancel();
      participantSub?.cancel();
    };

    return controller.stream;
  }

  /// Streams only the latest [limit] messages in a room.
  Stream<List<ChatMessage>> streamMessages(
    String conversationId, {
    int limit = 100,
  }) {
    return supabase
        .from('message')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: false)
        .limit(limit)
        .map(
          (rows) => rows
              .map((row) => ChatMessage.fromMap(row))
              .toList(growable: false),
        );
  }

  /// The other participant's read cursor. `.distinct()` matters: our own
  /// mark-read write makes this table emit, but the peer's value is unchanged,
  /// so nothing downstream should rebuild.
  Stream<DateTime?> streamPeerLastReadAt(String conversationId) {
    return supabase
        .from('conversation_participant')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .map((rows) {
          final peer = rows.firstWhere(
            (row) => row['profile_id'] != _uid,
            orElse: () => const <String, dynamic>{},
          );
          final value = peer['last_read_at'];
          if (value == null) return null;
          return DateTime.parse(value as String).toLocal();
        })
        .distinct();
  }

  /// Sends a message. Pass a client-generated [messageId] (uuid) to make
  /// optimistic UI exact: the realtime row comes back with the same id.
  Future<void> sendMessage({
    required String conversationId,
    String? text,
    File? imageFile,
    String? messageId,
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
      return;
    }

    await supabase.from('message').insert({
      if (messageId != null) 'id': messageId,
      'conversation_id': conversationId,
      'sender_id': _uid,
      'body': (trimmed == null || trimmed.isEmpty) ? null : trimmed,
      'attachment_url': attachmentPath,
      'attachment_type': attachmentType,
    });
  }

  /// Synchronous cache lookup so already-resolved images render instantly.
  String? peekAttachmentUrl(String path) {
    final cached = _urlCache[path];
    if (cached == null || !cached.expiresAt.isAfter(DateTime.now())) {
      return null;
    }
    return cached.url;
  }

  Future<String> resolveAttachmentUrl(String path) {
    final cached = peekAttachmentUrl(path);
    if (cached != null) return Future.value(cached);

    return supabase.storage
        .from(_attachmentsBucket)
        .createSignedUrl(path, 60 * 60)
        .then((url) {
          _urlCache[path] = (url: url, expiresAt: DateTime.now().add(_urlTtl));
          return url;
        });
  }

  Future<void> markMessagesAsRead(String conversationId) async {
    await supabase
        .from('conversation_participant')
        .update({'last_read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('conversation_id', conversationId)
        .eq('profile_id', _uid);
  }
}

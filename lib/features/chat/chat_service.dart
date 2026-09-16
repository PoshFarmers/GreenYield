import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/supabase/client.dart';
import '../../models/chat_models.dart';

/// Direct messaging service.
///
/// Messaging intentionally uses Supabase Realtime instead of PowerSync.
/// The important rule here is to keep Realtime subscriptions scoped and to
/// avoid re-querying the same data multiple times for one event.
class ChatService {
  const ChatService();

  static const _attachmentsBucket = 'message-attachments';

  static final Map<String, String> _urlCache = <String, String>{};

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
  /// The role is part of the participant snapshot in the database. This is
  /// important for users who can have more than one role; without it, a
  /// Farmer can accidentally see a Buyer/Driver thread belonging to another
  /// active role.
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
  /// Only two lightweight subscriptions are needed:
  ///  - conversation: a message INSERT bumps conversation.updated_at
  ///  - participant: a new conversation creates the recipient's row
  ///
  /// We deliberately do NOT subscribe to the entire message table here.
  /// Re-querying the thread list for every visible message event was a major
  /// source of unnecessary work.
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

      // RLS scopes this stream to conversations the signed-in user can see.
      // A new message updates conversation.updated_at through the database
      // trigger, so this single subscription is enough for existing threads.
      conversationSub = supabase
          .from('conversation')
          .stream(primaryKey: ['id'])
          .listen((_) => scheduleRefresh());

      // When a brand-new conversation is created for the other participant,
      // their conversation row already exists but their Realtime snapshot may
      // not contain the new participant relationship yet. This catches that
      // case without listening to the whole message table.
      participantSub = supabase
          .from('conversation_participant')
          .stream(primaryKey: ['id'])
          .eq('profile_id', _uid)
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

  /// Number of unread conversation threads for the active role.
  ///
  /// This uses one source of truth: conversation_participant.last_read_at.
  /// The old implementation merged a PowerSync notification count with a
  /// Realtime count, which could leave the two values out of sync.
  Stream<int> getUnreadConversationCountStream(String activeRole) {
    final controller = StreamController<int>.broadcast();
    StreamSubscription<List<Map<String, dynamic>>>? conversationSub;
    StreamSubscription<List<Map<String, dynamic>>>? participantSub;
    Timer? debounce;
    int requestVersion = 0;

    Future<void> refresh() async {
      final version = ++requestVersion;
      try {
        final value = await supabase.rpc(
          'unread_conversation_count',
          params: {'p_active_role': activeRole},
        );
        if (!controller.isClosed && version == requestVersion) {
          controller.add((value as int?) ?? 0);
        }
      } catch (error, stackTrace) {
        if (!controller.isClosed && version == requestVersion) {
          controller.addError(error, stackTrace);
        }
      }
    }

    void scheduleRefresh() {
      debounce?.cancel();
      debounce = Timer(const Duration(milliseconds: 200), refresh);
    }

    controller.onListen = () {
      refresh();

      // Message INSERT -> conversation.updated_at changes.
      conversationSub = supabase
          .from('conversation')
          .stream(primaryKey: ['id'])
          .listen((_) => scheduleRefresh());

      // Opening a chat changes the caller's last_read_at.
      participantSub = supabase
          .from('conversation_participant')
          .stream(primaryKey: ['id'])
          .eq('profile_id', _uid)
          .listen((_) => scheduleRefresh());
    };

    controller.onCancel = () {
      debounce?.cancel();
      requestVersion++;
      conversationSub?.cancel();
      participantSub?.cancel();
    };

    return controller.stream;
  }

  /// Streams only the latest [limit] messages in a room.
  ///
  /// Keeping the initial Realtime snapshot bounded is important for rooms
  /// with a long history. Older messages can be added later with pagination.
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
        });
  }

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
      return;
    }

    await supabase.from('message').insert({
      'conversation_id': conversationId,
      'sender_id': _uid,
      'body': (trimmed == null || trimmed.isEmpty) ? null : trimmed,
      'attachment_url': attachmentPath,
      'attachment_type': attachmentType,
    });
  }

  Future<String> resolveAttachmentUrl(String path) {
    final cached = _urlCache[path];
    if (cached != null) return Future.value(cached);

    return supabase.storage
        .from(_attachmentsBucket)
        .createSignedUrl(path, 60 * 60)
        .then((url) {
          _urlCache[path] = url;
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

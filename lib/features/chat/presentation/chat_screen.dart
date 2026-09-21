import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../core/widgets/app_secondary_header.dart';
import '../../../core/widgets/avatar_image.dart';
import '../../../models/chat_models.dart';
import '../application/chat_providers.dart';
import '../chat_service.dart';

enum _SendState { sent, sending, failed }

/// A message the user just sent that the realtime stream hasn't echoed back
/// yet. Its [id] is also used as the DB id, so it is dropped from the UI the
/// moment the real row arrives.
class _PendingMessage {
  final String id;
  final String? body;
  final File? image;
  final DateTime createdAt;
  bool failed = false;

  _PendingMessage({
    required this.id,
    this.body,
    this.image,
    required this.createdAt,
  });

  ChatMessage toMessage(String conversationId, String senderId) => ChatMessage(
    id: id,
    conversationId: conversationId,
    senderId: senderId,
    body: body,
    attachmentUrl: image?.path,
    attachmentType: image == null ? null : 'image',
    createdAt: createdAt,
  );
}

/// `chat_screen.dart` — the conversation room. Custom app bar with the
/// other participant's avatar/name, sender-vs-receiver bubbles, image
/// attachment picker/preview, auto-scroll to bottom, and timestamps.
/// Messages stream live via [chatMessagesProvider] (Supabase Realtime) and
/// sent messages appear instantly (optimistic) until the stream confirms them.
class ChatScreen extends ConsumerStatefulWidget {
  final String conversationId;
  final String otherName;
  final String? otherAvatarUrl;
  final String currentUserId;

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.otherName,
    required this.otherAvatarUrl,
    required this.currentUserId,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with WidgetsBindingObserver {
  final _textController = TextEditingController();

  /// Newest first (matches the reversed list).
  final List<_PendingMessage> _pending = [];

  File? _attachedImage;
  Timer? _readDebounce;

  /// Newest incoming message we've already marked as read.
  DateTime? _lastMarked;

  late final ProviderContainer _container;
  late final ChatService _chatService;

  @override
  void initState() {
    super.initState();

    // Capture these while the widget is mounted. The container can be used
    // to invalidate providers after dispose, and the service can finish a
    // pending mark-read write without accessing ref.
    _container = ProviderScope.containerOf(context, listen: false);
    _chatService = ref.read(chatServiceProvider);

    WidgetsBinding.instance.addObserver(this);

    // Messages may already be loaded (provider is kept alive), in which case
    // the listener in build() won't fire for them.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _maybeMarkRead(
        ref.read(chatMessagesProvider(widget.conversationId)).asData?.value,
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    // Don't drop a pending mark-read if the user leaves quickly.
    if (_readDebounce?.isActive ?? false) {
      _readDebounce!.cancel();
      _readDebounce = null;
      _markReadNow();
    }

    _textController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Realtime sockets can silently drop while backgrounded. Re-subscribe on
    // resume; the screen keeps showing the previous data while it reloads.
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(chatMessagesProvider(widget.conversationId));
      ref.invalidate(peerLastReadAtProvider(widget.conversationId));
    }
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );

    if (picked != null && mounted) {
      setState(() => _attachedImage = File(picked.path));
    }
  }

  Future<void> _send() async {
    final text = _textController.text.trim();
    final image = _attachedImage;
    if (text.isEmpty && image == null) return;

    final pending = _PendingMessage(
      id: const Uuid().v4(),
      body: text.isEmpty ? null : text,
      image: image,
      createdAt: DateTime.now(),
    );

    _textController.clear();
    setState(() {
      _attachedImage = null;
      _pending.insert(0, pending);
    });

    await _deliver(pending);
  }

  Future<void> _deliver(_PendingMessage pending) async {
    final service = ref.read(chatServiceProvider);

    try {
      await service.sendMessage(
        conversationId: widget.conversationId,
        text: pending.body,
        imageFile: pending.image,
        messageId: pending.id,
      );
      // Success: nothing to do. The realtime row carries the same id and
      // replaces the pending bubble.
    } catch (_) {
      if (!mounted) return;
      setState(() => pending.failed = true);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('failed_to_send_message'.tr())));
    }
  }

  void _retry(_PendingMessage pending) {
    setState(() => pending.failed = false);
    _deliver(pending);
  }

  void _discard(_PendingMessage pending) {
    setState(() => _pending.remove(pending));
  }

  /// Only writes `last_read_at` when something newer from the other person
  /// exists than what we've already marked. Without this, every emission
  /// (including our own sends) caused a write, which re-fired the participant
  /// stream and refetched the thread list.
  void _maybeMarkRead(List<ChatMessage>? messages) {
    if (messages == null || messages.isEmpty) return;

    DateTime? newestFromOther;
    for (final m in messages) {
      if (m.senderId == widget.currentUserId) continue;
      if (newestFromOther == null || m.createdAt.isAfter(newestFromOther)) {
        newestFromOther = m.createdAt;
      }
    }

    if (newestFromOther == null) return;

    final last = _lastMarked;
    if (last != null && !newestFromOther.isAfter(last)) return;

    _lastMarked = newestFromOther;
    _scheduleMarkAsRead();
  }

  void _scheduleMarkAsRead() {
    _readDebounce?.cancel();
    _readDebounce = Timer(const Duration(milliseconds: 150), () {
      _readDebounce = null;
      _markReadNow();
    });
  }

  /// Marks messages as read and refreshes the thread list only after the
  /// write succeeds. This keeps the unread badge independent of whether the
  /// corresponding Realtime UPDATE arrives.
  ///
  /// Uses the captured service and container because this operation can
  /// continue after this screen has been disposed.
  Future<void> _markReadNow() async {
    try {
      await _chatService.markMessagesAsRead(widget.conversationId);

      // Refresh the thread list and navigation badge deterministically.
      _container.invalidate(chatThreadsProvider);
    } catch (_) {
      // Allow a later message emission to retry the mark-read operation.
      _lastMarked = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(
      chatMessagesProvider(widget.conversationId),
    );

    // Read state is a side effect: keep it out of build().
    ref.listen<AsyncValue<List<ChatMessage>>>(
      chatMessagesProvider(widget.conversationId),
      (previous, next) => _maybeMarkRead(next.asData?.value),
    );

    final peerLastReadAt = ref
        .watch(peerLastReadAtProvider(widget.conversationId))
        .asData
        ?.value;

    return Scaffold(
      appBar: AppSecondaryHeader(
        titleWidget: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AvatarImage(path: widget.otherAvatarUrl, radius: 18),
            const SizedBox(width: 10),
            Flexible(
              child: Text(widget.otherName, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: messagesAsync.when(
              // Keep showing the previous list while reloading or after a
              // transient stream error (e.g. after backgrounding).
              skipLoadingOnReload: true,
              skipError: true,
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) =>
                  Center(child: Text('failed_to_load_chats'.tr())),
              data: (messages) {
                final streamIds = {for (final m in messages) m.id};
                final pending = _pending
                    .where((p) => !streamIds.contains(p.id))
                    .toList();

                final ids = <String>[
                  for (final p in pending) p.id,
                  for (final m in messages) m.id,
                ];
                final indexById = {
                  for (var i = 0; i < ids.length; i++) ids[i]: i,
                };

                return ListView.builder(
                  // reverse:true renders index 0 at the bottom. Pending
                  // messages are newest, so they come first; then the stream
                  // (already newest-first).
                  reverse: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  itemCount: ids.length,
                  findChildIndexCallback: (key) {
                    if (key is ValueKey<String>) return indexById[key.value];
                    return null;
                  },
                  itemBuilder: (context, index) {
                    if (index < pending.length) {
                      final p = pending[index];
                      return _MessageBubble(
                        key: ValueKey(p.id),
                        message: p.toMessage(
                          widget.conversationId,
                          widget.currentUserId,
                        ),
                        isMine: true,
                        peerLastReadAt: null,
                        localImage: p.image,
                        sendState: p.failed
                            ? _SendState.failed
                            : _SendState.sending,
                        onTap: p.failed ? () => _retry(p) : null,
                        onLongPress: p.failed ? () => _discard(p) : null,
                      );
                    }

                    final message = messages[index - pending.length];
                    return _MessageBubble(
                      key: ValueKey(message.id),
                      message: message,
                      isMine: message.senderId == widget.currentUserId,
                      peerLastReadAt: peerLastReadAt,
                    );
                  },
                );
              },
            ),
          ),
          if (_attachedImage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      _attachedImage!,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _attachedImage = null),
                  ),
                ],
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'attach_image'.tr(),
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: _pickImage,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'type_a_message'.tr(),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    icon: const Icon(Icons.send),
                    onPressed: _send,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMine;
  final DateTime? peerLastReadAt;

  /// Set for optimistic image messages that haven't been uploaded yet.
  final File? localImage;
  final _SendState sendState;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.peerLastReadAt,
    this.localImage,
    this.sendState = _SendState.sent,
    this.onTap,
    this.onLongPress,
  });

  String _timestamp() {
    final at = message.createdAt;
    final hour = at.hour % 12 == 0 ? 12 : at.hour % 12;
    final minute = at.minute.toString().padLeft(2, '0');
    final period = at.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bubbleColor = isMine
        ? theme.colorScheme.primary
        : theme.colorScheme.surface;
    final textColor = isMine
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;
    final isSeen =
        isMine &&
        sendState == _SendState.sent &&
        peerLastReadAt != null &&
        !message.createdAt.isAfter(peerLastReadAt!);

    final IconData statusIcon;
    final Color statusColor;
    switch (sendState) {
      case _SendState.sending:
        statusIcon = Icons.access_time;
        statusColor = textColor.withValues(alpha: 0.7);
      case _SendState.failed:
        statusIcon = Icons.error_outline;
        statusColor = Colors.redAccent;
      case _SendState.sent:
        statusIcon = isSeen ? Icons.done_all : Icons.done;
        statusColor = isSeen
            ? Colors.lightBlueAccent
            : textColor.withValues(alpha: 0.7);
    }

    final bubble = Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(10),
        constraints: BoxConstraints(
          // sizeOf: don't rebuild every bubble on keyboard/inset changes.
          maxWidth: MediaQuery.sizeOf(context).width * 0.72,
        ),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isMine ? 14 : 2),
            bottomRight: Radius.circular(isMine ? 2 : 14),
          ),
          border: isMine ? null : Border.all(color: theme.colorScheme.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.isImage)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: localImage != null
                    ? Image.file(
                        localImage!,
                        width: _AttachmentImageState.size,
                        height: _AttachmentImageState.size,
                        fit: BoxFit.cover,
                      )
                    : _AttachmentImage(path: message.attachmentUrl!),
              ),
            if (message.body != null && message.body!.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(top: message.isImage ? 6 : 0),
                child: Text(message.body!, style: TextStyle(color: textColor)),
              ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _timestamp(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: textColor.withValues(alpha: 0.7),
                  ),
                ),
                if (isMine) ...[
                  const SizedBox(width: 4),
                  Icon(statusIcon, size: 14, color: statusColor),
                ],
              ],
            ),
          ],
        ),
      ),
    );

    if (onTap == null && onLongPress == null) return bubble;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: bubble,
    );
  }
}

/// Resolves the signed URL once (and instantly when it's already cached) and
/// renders into a fixed box so the list never jumps when the image loads.
class _AttachmentImage extends StatefulWidget {
  final String path;

  const _AttachmentImage({required this.path});

  @override
  State<_AttachmentImage> createState() => _AttachmentImageState();
}

class _AttachmentImageState extends State<_AttachmentImage> {
  static const size = 180.0;

  String? _url;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant _AttachmentImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _url = null;
      _failed = false;
      _resolve();
    }
  }

  Future<void> _resolve() async {
    const service = ChatService();
    final path = widget.path;

    final cached = service.peekAttachmentUrl(path);
    if (cached != null) {
      _url = cached;
      return;
    }

    try {
      final url = await service.resolveAttachmentUrl(path);
      if (!mounted || widget.path != path) return;
      setState(() => _url = url);
    } catch (_) {
      if (!mounted || widget.path != path) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = _url;

    Widget placeholder(Widget child) => SizedBox(
      width: size,
      height: size,
      child: Center(child: child),
    );

    if (_failed) {
      return placeholder(
        Icon(Icons.broken_image_outlined, color: theme.colorScheme.outline),
      );
    }

    if (url == null) {
      return placeholder(const CircularProgressIndicator());
    }

    return Image.network(
      url,
      width: size,
      height: size,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : placeholder(const CircularProgressIndicator()),
      errorBuilder: (context, error, stackTrace) => placeholder(
        Icon(Icons.broken_image_outlined, color: theme.colorScheme.outline),
      ),
    );
  }
}

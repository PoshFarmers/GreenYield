import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/widgets/avatar_image.dart';
import '../../../models/chat_models.dart';
import '../application/chat_providers.dart';
import '../chat_service.dart';

/// `chat_screen.dart` — the conversation room. Custom app bar with the
/// other participant's avatar/name, sender-vs-receiver bubbles, image
/// attachment picker/preview, auto-scroll to bottom, and timestamps.
/// Messages stream live via [chatMessagesProvider] (Supabase Realtime).
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

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _textController = TextEditingController();
  File? _pendingImage;
  bool _isSending = false;
  Timer? _readDebounce;

  @override
  void dispose() {
    _readDebounce?.cancel();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (picked != null) {
      setState(() => _pendingImage = File(picked.path));
    }
  }

  Future<void> _send() async {
    final text = _textController.text;
    final image = _pendingImage;
    if (text.trim().isEmpty && image == null) return;

    setState(() => _isSending = true);
    _textController.clear();
    setState(() => _pendingImage = null);

    try {
      await ref
          .read(chatServiceProvider)
          .sendMessage(
            conversationId: widget.conversationId,
            text: text,
            imageFile: image,
          );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('failed_to_send_message'.tr())));
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _scheduleMarkAsRead() {
    _readDebounce?.cancel();
    _readDebounce = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      ref
          .read(chatServiceProvider)
          .markMessagesAsRead(widget.conversationId)
          .catchError((_) {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(
      chatMessagesProvider(widget.conversationId),
    );

    // Read state is a side effect. Keep it out of build() and debounce it
    // so a burst of incoming messages causes one database write, not one
    // write per message.
    ref.listen<AsyncValue<List<ChatMessage>>>(
      chatMessagesProvider(widget.conversationId),
      (previous, next) {
        if (next.hasValue) _scheduleMarkAsRead();
      },
    );

    final peerLastReadAt = ref
        .watch(peerLastReadAtProvider(widget.conversationId))
        .asData
        ?.value;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            AvatarImage(path: widget.otherAvatarUrl, radius: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(widget.otherName, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: messagesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) =>
                  Center(child: Text('failed_to_load_chats'.tr())),
              data: (messages) {
                return ListView.builder(
                  // reverse:true renders index 0 at the bottom and
                  // scrolls upward — combined with descending ordering
                  // in streamMessages() (newest = index 0) this gives
                  // the correct WhatsApp-style layout with zero jank.
                  reverse: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final isMine = message.senderId == widget.currentUserId;
                    return _MessageBubble(
                      message: message,
                      isMine: isMine,
                      peerLastReadAt: peerLastReadAt,
                    );
                  },
                );
              },
            ),
          ),
          if (_pendingImage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      _pendingImage!,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _pendingImage = null),
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
                    onPressed: _isSending ? null : _pickImage,
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
                    onPressed: _isSending ? null : _send,
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

  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.peerLastReadAt,
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
        peerLastReadAt != null &&
        !message.createdAt.isAfter(peerLastReadAt!);

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
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
                child: FutureBuilder<String>(
                  future: const ChatService().resolveAttachmentUrl(
                    message.attachmentUrl!,
                  ),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const SizedBox(
                        width: 180,
                        height: 180,
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    return Image.network(
                      snapshot.data!,
                      width: 180,
                      fit: BoxFit.cover,
                    );
                  },
                ),
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
                  Icon(
                    isSeen ? Icons.done_all : Icons.done,
                    size: 14,
                    color: isSeen
                        ? Colors.lightBlueAccent
                        : textColor.withValues(alpha: 0.7),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

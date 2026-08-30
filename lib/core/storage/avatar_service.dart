import 'dart:typed_data';

import '../media/media_service.dart';

/// Avatars are just one "purpose" of the generic media queue now — this
/// class only knows the avatar-specific bucket/path convention;
/// everything else (offline queuing, retry, caching) lives in
/// MediaService / MediaQueueDb / MediaUploader.
///
/// Public API (`upload`) is unchanged from before, so
/// complete_profile_screen.dart and the buyer/driver/farmer edit
/// screens don't need any changes.
class AvatarService {
  static const _bucket = 'avatars';
  final MediaService _media;

  AvatarService({MediaService? media})
    : _media = media ?? MediaService.instance;

  /// Enqueues the avatar locally and returns immediately — works fully
  /// offline. The actual bytes upload happens in the background via
  /// MediaUploader once connectivity is available. Previously this
  /// awaited a live Supabase Storage call directly, so if it threw
  /// while offline, the whole profile-save aborted (see AuthService/
  /// *ProfileService calls in each edit screen's _submit()) — that
  /// failure mode is gone now.
  Future<String> upload({
    required String userId,
    required Uint8List bytes,
    required String fileName,
  }) {
    final ext = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : 'jpg';
    final path = '$userId/avatar.$ext';
    final contentType = switch (ext) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };

    return _media.enqueueUpload(
      bucket: _bucket,
      remotePath: path,
      bytes: bytes,
      contentType: contentType,
      purpose: 'avatar',
      ownerId: userId,
    );
  }
}

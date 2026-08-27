import 'dart:io';

import '../media/media_service.dart';

/// Thin avatar-flavored wrapper over the generic MediaService cache —
/// same public API as before (getAvatarFile/invalidate), so
/// AvatarImage and the edit screens don't need to change. Offline-
/// picked avatars now show immediately too: MediaService seeds the
/// cache with the local file the moment it's enqueued, before any
/// upload has actually happened.
class AvatarCacheService {
  static const _bucket = 'avatars';
  final MediaService _media;

  AvatarCacheService({MediaService? media})
    : _media = media ?? MediaService.instance;

  Future<File> getAvatarFile(String path) {
    return _media.getDisplayFile(bucket: _bucket, remotePath: path);
  }

  /// Call after a successful edit so a re-fetched signed URL replaces
  /// the stale cached one under the same key, same as before.
  Future<void> invalidate(String path) =>
      _media.invalidateCache(bucket: _bucket, remotePath: path);
}

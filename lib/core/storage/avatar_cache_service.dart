import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'avatar_service.dart';

class AvatarCacheManager extends CacheManager {
  static const key = 'avatarCache';

  static final AvatarCacheManager _instance = AvatarCacheManager._();
  factory AvatarCacheManager() => _instance;

  AvatarCacheManager._()
    : super(
        Config(
          key,
          stalePeriod: const Duration(days: 7),
          maxNrOfCacheObjects: 200,
        ),
      );
}

/// Returns a cached avatar file for a given storage object path,
/// minting a fresh signed URL only on a cache miss. Caching by [path]
/// (stable) rather than the signed URL (rotates every call) is the
/// whole point — otherwise every screen open would re-download.
class AvatarCacheService {
  final _avatarService = AvatarService();
  final _cacheManager = AvatarCacheManager();

  Future<File> getAvatarFile(String path) async {
    final cached = await _cacheManager.getFileFromCache(path);
    if (cached != null) return cached.file;

    final signedUrl = await _avatarService.signedUrl(path);
    final fileInfo = await _cacheManager.downloadFile(signedUrl, key: path);
    return fileInfo.file;
  }

  /// Call after a successful avatar upload so the new image replaces
  /// the stale cached one under the same key, rather than waiting a
  /// week for stalePeriod to expire.
  Future<void> invalidate(String path) => _cacheManager.removeFile(path);
}

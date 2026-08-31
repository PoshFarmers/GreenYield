import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../supabase/client.dart';

class _MediaCacheManager extends CacheManager {
  static const key = 'mediaCache';
  static final _instance = _MediaCacheManager._();
  factory _MediaCacheManager() => _instance;
  _MediaCacheManager._()
    : super(
        Config(
          key,
          stalePeriod: const Duration(days: 7),
          maxNrOfCacheObjects: 500,
        ),
      );
}

/// Generic disk cache for any bucket/path pair, keyed by `bucket:path`
/// so it's stable across signed-URL rotation. Replaces the
/// avatar-specific AvatarCacheManager — every media purpose shares this
/// one cache instead of each feature building its own.
class MediaCache {
  static final MediaCache instance = MediaCache._();
  MediaCache._();

  final _manager = _MediaCacheManager();

  String _cacheKey(String bucket, String remotePath) => '$bucket:$remotePath';

  /// Seeds the cache directly with a local file — used right after
  /// enqueueUpload() so the picked file shows immediately, before any
  /// upload has actually happened (works offline).
  Future<void> putLocalFile({
    required String bucket,
    required String remotePath,
    required File file,
  }) async {
    final bytes = await file.readAsBytes();
    final key = _cacheKey(bucket, remotePath);
    await _manager.putFile(key, bytes, key: key);
  }

  Future<File> getFile({
    required String bucket,
    required String remotePath,
    bool public = false,
    int signedUrlExpiresIn = 3600,
  }) async {
    final key = _cacheKey(bucket, remotePath);
    final cached = await _manager.getFileFromCache(key);
    if (cached != null) return cached.file;

    // Public buckets skip the createSignedUrl round-trip entirely --
    // getPublicUrl is a local string build, no network call.
    final url = public
        ? supabase.storage.from(bucket).getPublicUrl(remotePath)
        : await supabase.storage
              .from(bucket)
              .createSignedUrl(remotePath, signedUrlExpiresIn);
    final fileInfo = await _manager.downloadFile(url, key: key);
    return fileInfo.file;
  }

  Future<void> invalidate({
    required String bucket,
    required String remotePath,
  }) => _manager.removeFile(_cacheKey(bucket, remotePath));
}

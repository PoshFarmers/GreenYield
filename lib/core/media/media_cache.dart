import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import '../supabase/client.dart';
import 'media_size.dart';

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

/// Generic disk cache for any bucket/path pair, keyed by
/// `bucket:path:size` so thumbnail and full-resolution variants of the
/// same image are cached — and evicted — independently. A small cart
/// or grid thumbnail no longer downloads or decodes the full-size
/// original just to show a 56px image.
class MediaCache {
  static final MediaCache instance = MediaCache._();
  MediaCache._();

  final _manager = _MediaCacheManager();

  String _cacheKey(String bucket, String remotePath, MediaSize size) =>
      '$bucket:$remotePath:${size.name}';

  /// Seeds both tiers from the same local bytes right after
  /// enqueueUpload(), so whichever tier a widget asks for next shows
  /// the freshly picked photo immediately (works offline).
  Future<void> putLocalFile({
    required String bucket,
    required String remotePath,
    required File file,
  }) async {
    final bytes = await file.readAsBytes();

    final fullKey = _cacheKey(bucket, remotePath, MediaSize.full);
    final fullFile = await _manager.putFile(fullKey, bytes, key: fullKey);
    await FileImage(fullFile).evict();

    final thumbBytes = _downscale(bytes) ?? bytes;
    final thumbKey = _cacheKey(bucket, remotePath, MediaSize.thumbnail);
    final thumbFile = await _manager.putFile(
      thumbKey,
      thumbBytes,
      key: thumbKey,
    );
    await FileImage(thumbFile).evict();
  }

  Future<File> getFile({
    required String bucket,
    required String remotePath,
    bool public = false,
    int signedUrlExpiresIn = 3600,
    MediaSize size = MediaSize.full,
  }) async {
    final key = _cacheKey(bucket, remotePath, size);
    final cached = await _manager.getFileFromCache(key);
    if (cached != null) return cached.file;

    final url = public
        ? supabase.storage.from(bucket).getPublicUrl(remotePath)
        : await supabase.storage
              .from(bucket)
              .createSignedUrl(remotePath, signedUrlExpiresIn);

    if (size == MediaSize.full) {
      final fileInfo = await _manager.downloadFile(url, key: key);
      return fileInfo.file;
    }

    // Thumbnail tier: download once, downscale, cache the smaller
    // result under its own key so future thumbnail requests never
    // re-download or re-decode the full-size original.
    final response = await http.get(Uri.parse(url));
    final downscaled = _downscale(response.bodyBytes) ?? response.bodyBytes;
    final file = await _manager.putFile(key, downscaled, key: key);
    return file;
  }

  Uint8List? _downscale(Uint8List bytes) {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      if (decoded.width <= MediaSize.thumbnailMaxDimension &&
          decoded.height <= MediaSize.thumbnailMaxDimension) {
        return img.encodeJpg(decoded, quality: 85);
      }
      final resized = img.copyResize(
        decoded,
        width: decoded.width >= decoded.height
            ? MediaSize.thumbnailMaxDimension
            : null,
        height: decoded.height > decoded.width
            ? MediaSize.thumbnailMaxDimension
            : null,
      );
      return img.encodeJpg(resized, quality: 85);
    } catch (_) {
      // Fall back to the original bytes rather than losing the image.
      return null;
    }
  }

  Future<void> invalidate({
    required String bucket,
    required String remotePath,
  }) async {
    await _manager.removeFile(_cacheKey(bucket, remotePath, MediaSize.full));
    await _manager.removeFile(
      _cacheKey(bucket, remotePath, MediaSize.thumbnail),
    );
  }
}

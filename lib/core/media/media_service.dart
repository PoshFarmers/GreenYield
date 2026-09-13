import 'dart:io';
import 'dart:typed_data';
import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'media_attachment.dart';
import 'media_cache.dart';
import 'media_queue_db.dart';
import 'media_uploader.dart';

/// Generic media API for the whole app — the replacement for
/// avatar-only upload/cache code. Any feature (avatars, marketplace
/// listing photos, delivery proof shots, ...) enqueues through here
/// instead of writing its own upload/cache pair. See AvatarService for
/// an example of a thin feature-specific wrapper around this.
class MediaService {
  static final MediaService instance = MediaService._();
  MediaService._();

  final _db = MediaQueueDb.instance;
  final _cache = MediaCache.instance;
  static const _uuid = Uuid();

  /// Copies [bytes] to local disk and queues the upload. Returns
  /// immediately — the remote path is deterministic and handed back
  /// right away so callers (e.g. saving a profile row that references
  /// this path) don't need to wait for the network. Works fully
  /// offline; the queue drains via MediaUploader once connectivity
  /// returns.
  Future<String> enqueueUpload({
    required String bucket,
    required String remotePath,
    required Uint8List bytes,
    required String purpose,
    String? ownerId,
    String? contentType,
  }) async {
    final dir = await getApplicationSupportDirectory();
    final localPath = p.join(
      dir.path,
      'media_queue',
      '${_uuid.v4()}_${p.basename(remotePath)}',
    );
    final file = File(localPath);
    await file.create(recursive: true);
    await file.writeAsBytes(bytes);

    final now = DateTime.now();
    await _db.upsert(
      MediaAttachment(
        id: _uuid.v4(),
        bucket: bucket,
        remotePath: remotePath,
        localPath: localPath,
        ownerId: ownerId,
        purpose: purpose,
        contentType: contentType,
        state: AttachmentState.queuedUpload,
        createdAt: now,
        updatedAt: now,
      ),
    );

    // Seed the display cache immediately with the local bytes, so
    // anything reading this path (e.g. AvatarImage) shows the picked
    // file right away instead of a stale remote one.
    await _cache.putLocalFile(
      bucket: bucket,
      remotePath: remotePath,
      file: file,
    );

    unawaited(
      MediaUploader.instance.drain(),
    ); // fire-and-forget; no-op if offline
    return remotePath;
  }

  Stream<List<MediaAttachment>> watchByOwner(
    String ownerId, {
    String? purpose,
  }) {
    final where = purpose == null
        ? 'owner_id = ?'
        : 'owner_id = ? AND purpose = ?';
    final args = purpose == null ? [ownerId] : [ownerId, purpose];
    return _db.watch(where: where, whereArgs: args, orderBy: 'created_at DESC');
  }

  /// Best file to display for [remotePath] right now: a cached
  /// download if one exists (this also covers the "just enqueued"
  /// case, since enqueueUpload seeds the cache directly), or a fresh
  /// download via a signed URL.
  Future<File> getDisplayFile({
    required String bucket,
    required String remotePath,
    bool public = false,
    int signedUrlExpiresIn = 3600,
  }) {
    return _cache.getFile(
      bucket: bucket,
      remotePath: remotePath,
      public: public,
      signedUrlExpiresIn: signedUrlExpiresIn,
    );
  }

  Future<void> invalidateCache({
    required String bucket,
    required String remotePath,
  }) => _cache.invalidate(bucket: bucket, remotePath: remotePath);

  Future<void> deleteAttachment(String id) async {
    final attachment = await _db.getById(id);
    if (attachment == null) return;
    await _db.upsert(attachment.copyWith(state: AttachmentState.queuedDelete));
    unawaited(MediaUploader.instance.drain());
  }
}

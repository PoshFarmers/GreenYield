import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/client.dart';
import 'media_attachment.dart';
import 'media_queue_db.dart';

/// Background worker that drains the media queue whenever the device
/// is online. Independent of PowerSync entirely — this only talks to
/// Supabase Storage directly, same as AvatarService did before; it's
/// just decoupled from the profile-save flow now.
class MediaUploader {
  static final MediaUploader instance = MediaUploader._();
  MediaUploader._();

  final _db = MediaQueueDb.instance;
  bool _draining = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  /// Call once at app startup (e.g. alongside initSupabase()/initPowerSync()
  /// in main.dart) to start listening for connectivity changes.
  void start() {
    _connectivitySub ??= Connectivity().onConnectivityChanged.listen((results) {
      if (!results.contains(ConnectivityResult.none)) {
        drain();
      }
    });
    drain();
  }

  void dispose() {
    _connectivitySub?.cancel();
    _connectivitySub = null;
  }

  /// Processes every queued row once, in order. Safe to call repeatedly —
  /// re-entrant calls are no-ops while a drain is already in progress.
  Future<void> drain() async {
    if (_draining) return;
    _draining = true;
    try {
      for (final attachment in await _db.pendingUploads()) {
        await _uploadOne(attachment);
      }
      for (final attachment in await _db.pendingDeletes()) {
        await _deleteOne(attachment);
      }
    } finally {
      _draining = false;
    }
  }

  Future<void> _uploadOne(MediaAttachment attachment) async {
    await _db.upsert(attachment.copyWith(state: AttachmentState.uploading));
    try {
      final bytes = await File(attachment.localPath).readAsBytes();
      await supabase.storage
          .from(attachment.bucket)
          .uploadBinary(
            attachment.remotePath,
            bytes,
            fileOptions: FileOptions(
              contentType: attachment.contentType,
              upsert: true,
            ),
          );
      await _db.upsert(
        attachment.copyWith(state: AttachmentState.synced, errorMessage: null),
      );
    } catch (e) {
      // Left as `failed` rather than retried immediately — `drain()`
      // picks failed rows up again next time it runs (e.g. next
      // connectivity change), so a single bad network blip doesn't spin.
      await _db.upsert(
        attachment.copyWith(
          state: AttachmentState.failed,
          errorMessage: e.toString(),
        ),
      );
    }
  }

  Future<void> _deleteOne(MediaAttachment attachment) async {
    try {
      await supabase.storage.from(attachment.bucket).remove([
        attachment.remotePath,
      ]);
      await _db.delete(attachment.id);
    } catch (e) {
      await _db.upsert(
        attachment.copyWith(
          state: AttachmentState.failed,
          errorMessage: e.toString(),
        ),
      );
    }
  }
}

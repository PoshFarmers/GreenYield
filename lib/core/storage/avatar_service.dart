import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/client.dart';

/// Uploads the signed-in user's avatar to the `avatars` storage bucket
/// and returns the object path to store in `profile.avatar_url`.
///
/// The bucket is private (see the accompanying storage migration) — each
/// user can only read/write objects under their own `<uid>/` prefix, so
/// `avatar_url` stores an object path rather than a public URL.
class AvatarService {
  static const _bucket = 'avatars';

  Future<String> upload({
    required String userId,
    required Uint8List bytes,
    required String fileName,
  }) async {
    final ext = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : 'jpg';
    final path = '$userId/avatar.$ext';
    final contentType = switch (ext) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };

    await supabase.storage
        .from(_bucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );

    return path;
  }

  /// Signed URL good for [expiresIn] seconds — use this to actually
  /// display an avatar stored under a private bucket.
  Future<String> signedUrl(String path, {int expiresIn = 3600}) {
    return supabase.storage.from(_bucket).createSignedUrl(path, expiresIn);
  }
}

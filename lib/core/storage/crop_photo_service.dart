import 'dart:typed_data';

import '../media/media_service.dart';

/// Uploads a farmer's per-crop photo (farmer_crop.image_url), following
/// the same bucket/path convention and offline-queue behavior as
/// AvatarService — see that class for the rationale.
class CropPhotoService {
  static const _bucket = 'crop-photos';
  final MediaService _media;

  CropPhotoService({MediaService? media})
    : _media = media ?? MediaService.instance;

  Future<String> upload({
    required String userId,
    required String cropId,
    required Uint8List bytes,
    required String fileName,
  }) =>
      _uploadAt(userId: userId, name: cropId, bytes: bytes, fileName: fileName);

  /// Per-listing photo override (produce_listing.image_url). Keyed by
  /// listing id rather than crop id so publishing a listing never
  /// overwrites the farmer's standing farmer_crop photo.
  Future<String> uploadListingPhoto({
    required String userId,
    required String listingId,
    required Uint8List bytes,
    required String fileName,
  }) => _uploadAt(
    userId: userId,
    name: 'listing_$listingId',
    bytes: bytes,
    fileName: fileName,
  );

  Future<String> _uploadAt({
    required String userId,
    required String name,
    required Uint8List bytes,
    required String fileName,
  }) {
    final ext = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : 'jpg';
    final path = '$userId/$name.$ext';
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
      purpose: 'farmer_crop_photo',
      ownerId: userId,
    );
  }
}

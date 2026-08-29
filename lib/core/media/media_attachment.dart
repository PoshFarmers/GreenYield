/// Lifecycle state of a queued media file, independent of what the file
/// actually is (avatar, listing photo, proof of delivery, ...).
enum AttachmentState {
  queuedUpload,
  uploading,
  synced,
  queuedDelete,
  failed;

  static AttachmentState fromDb(String value) =>
      AttachmentState.values.firstWhere((s) => s.name == value);
}

/// One row in the local media queue. Deliberately generic — [purpose]
/// is a free-form string ('avatar', 'crop_listing_photo',
/// 'delivery_proof', ...) rather than a hardcoded enum, so new features
/// can start queuing their own media without editing this file.
class MediaAttachment {
  final String id;
  final String bucket;
  final String remotePath;
  final String localPath;
  final String? ownerId;
  final String purpose;
  final String? contentType;
  final AttachmentState state;
  final String? errorMessage;
  final DateTime createdAt;
  final DateTime updatedAt;

  const MediaAttachment({
    required this.id,
    required this.bucket,
    required this.remotePath,
    required this.localPath,
    this.ownerId,
    required this.purpose,
    this.contentType,
    required this.state,
    this.errorMessage,
    required this.createdAt,
    required this.updatedAt,
  });

  MediaAttachment copyWith({AttachmentState? state, String? errorMessage}) {
    return MediaAttachment(
      id: id,
      bucket: bucket,
      remotePath: remotePath,
      localPath: localPath,
      ownerId: ownerId,
      purpose: purpose,
      contentType: contentType,
      state: state ?? this.state,
      errorMessage: errorMessage,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  factory MediaAttachment.fromMap(Map<String, dynamic> map) {
    return MediaAttachment(
      id: map['id'] as String,
      bucket: map['bucket'] as String,
      remotePath: map['remote_path'] as String,
      localPath: map['local_path'] as String,
      ownerId: map['owner_id'] as String?,
      purpose: map['purpose'] as String,
      contentType: map['content_type'] as String?,
      state: AttachmentState.fromDb(map['state'] as String),
      errorMessage: map['error_message'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'bucket': bucket,
    'remote_path': remotePath,
    'local_path': localPath,
    'owner_id': ownerId,
    'purpose': purpose,
    'content_type': contentType,
    'state': state.name,
    'error_message': errorMessage,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };
}

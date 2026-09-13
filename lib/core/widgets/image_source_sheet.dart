import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// The "Take Photo" / "Choose from Gallery" bottom sheet shown wherever
/// a photo can be picked (avatar, crop photo, listing photo, ...).
/// Resolves to the picked source, or null if dismissed without a
/// choice — the caller still owns the actual `ImagePicker().pickImage`
/// call, so it can set its own `maxWidth`/`imageQuality`.
Future<ImageSource?> showImageSourceSheet(BuildContext context) {
  return showModalBottomSheet<ImageSource>(
    context: context,
    builder: (context) => SafeArea(
      child: Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text('take_photo'.tr()),
            onTap: () => Navigator.of(context).pop(ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text('choose_from_gallery'.tr()),
            onTap: () => Navigator.of(context).pop(ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
}

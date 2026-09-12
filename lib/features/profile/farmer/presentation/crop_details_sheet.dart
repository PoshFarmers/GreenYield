import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/widgets/media_image.dart';
import '../crop_price_bounds.dart';

/// What the farmer entered for one crop. [imageBytes] is null when they
/// didn't pick a new photo — the caller should keep whatever path was
/// already stored rather than clearing it.
class CropDetails {
  final String? description;
  final double price;
  final Uint8List? imageBytes;
  final String? imageFileName;

  const CropDetails({
    required this.price,
    this.description,
    this.imageBytes,
    this.imageFileName,
  });
}

/// Shared photo/description/price editor for a single crop — used both
/// by onboarding ("Your Crops") and by the Crops Grown section of the
/// farmer profile, so the two can't drift apart.
///
/// Returns null if dismissed. [onRemove] adds a Remove button; it fires
/// after the sheet closes.
Future<CropDetails?> showCropDetailsSheet({
  required BuildContext context,
  required String cropName,
  String? initialDescription,
  double? initialPrice,
  String? existingImagePath,
  String? fallbackImageUrl,
  VoidCallback? onRemove,
}) {
  return showModalBottomSheet<CropDetails>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _CropDetailsSheet(
      cropName: cropName,
      initialDescription: initialDescription,
      initialPrice: initialPrice,
      existingImagePath: existingImagePath,
      fallbackImageUrl: fallbackImageUrl,
      onRemove: onRemove,
    ),
  );
}

class _CropDetailsSheet extends StatefulWidget {
  final String cropName;
  final String? initialDescription;
  final double? initialPrice;
  final String? existingImagePath;
  final String? fallbackImageUrl;
  final VoidCallback? onRemove;

  const _CropDetailsSheet({
    required this.cropName,
    this.initialDescription,
    this.initialPrice,
    this.existingImagePath,
    this.fallbackImageUrl,
    this.onRemove,
  });

  @override
  State<_CropDetailsSheet> createState() => _CropDetailsSheetState();
}

class _CropDetailsSheetState extends State<_CropDetailsSheet> {
  late final TextEditingController _descController;
  late final ({double min, double max}) _bounds;
  late double _price;
  Uint8List? _imageBytes;
  String? _imageFileName;

  @override
  void initState() {
    super.initState();
    _bounds = priceBoundsFor(widget.cropName);
    _descController = TextEditingController(
      text: widget.initialDescription ?? '',
    );
    _price = widget.initialPrice ?? (_bounds.min + _bounds.max) / 2;
  }

  @override
  void dispose() {
    _descController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1024,
      imageQuality: 85,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      _imageBytes = bytes;
      _imageFileName = picked.name;
    });
  }

  void _showImageSourceSheet() {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text('take_photo'.tr()),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text('choose_from_gallery'.tr()),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasOwnPhoto = _imageBytes != null || widget.existingImagePath != null;
    final hasAnyPhoto = hasOwnPhoto || widget.fallbackImageUrl != null;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.cropName, style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            if (hasAnyPhoto)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  height: 140,
                  width: double.infinity,
                  child: _imageBytes != null
                      ? Image.memory(_imageBytes!, fit: BoxFit.cover)
                      : widget.existingImagePath != null
                      ? MediaImage(
                          path: widget.existingImagePath,
                          bucket: 'crop-photos',
                          placeholder: Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                          ),
                        )
                      : MediaImage(
                          path: widget.fallbackImageUrl,
                          bucket: 'crop-fallback-images',
                          public: true,
                          placeholder: Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                          ),
                        ),
                ),
              ),
            if (hasAnyPhoto) const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _showImageSourceSheet,
              icon: const Icon(Icons.camera_alt_outlined),
              label: Text(
                hasAnyPhoto ? 'change_photo'.tr() : 'add_crop_photo'.tr(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descController,
              maxLength: 130,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'crop_description_hint'.tr(),
              ),
            ),
            Text('set_price_per_kg'.tr(), style: theme.textTheme.labelLarge),
            Slider(
              value: _price.clamp(_bounds.min, _bounds.max),
              min: _bounds.min,
              max: _bounds.max,
              onChanged: (value) => setState(() => _price = value),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${'market_min'.tr()}: Rs ${_bounds.min.toStringAsFixed(0)}',
                  style: theme.textTheme.bodySmall,
                ),
                Text(
                  '${'market_max'.tr()}: Rs ${_bounds.max.toStringAsFixed(0)}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Rs ${_price.toStringAsFixed(0)}',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                if (widget.onRemove != null) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        widget.onRemove!();
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                      ),
                      child: Text('remove'.tr()),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      final description = _descController.text.trim();
                      Navigator.of(context).pop(
                        CropDetails(
                          description: description.isEmpty ? null : description,
                          price: _price,
                          imageBytes: _imageBytes,
                          imageFileName: _imageFileName,
                        ),
                      );
                    },
                    child: Text('save'.tr()),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

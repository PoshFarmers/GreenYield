import 'package:flutter/material.dart';

import '../../../../core/widgets/media_image.dart';
import '../../../../models/farmer_profile.dart';

/// One selectable crop tile in the onboarding crop grid. Shows the crop's
/// `fallback_image_url` (from the `crop-fallback-images` public bucket)
/// when available, falling back to a category icon otherwise.
class CropTile extends StatelessWidget {
  final Crop crop;
  final bool isSelected;
  final VoidCallback onTap;

  const CropTile({
    super.key,
    required this.crop,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categoryIcon = Icon(
      crop.category == 'fruit' ? Icons.apple : Icons.eco,
      size: 28,
      color: theme.colorScheme.primary,
    );

    final borderRadius = BorderRadius.circular(12);

    return InkWell(
      borderRadius: borderRadius,
      onTap: onTap,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: borderRadius,
            child: Container(
              color: isSelected
                  ? theme.colorScheme.primary.withValues(alpha: 0.12)
                  : theme.colorScheme.surfaceContainerHighest,
              child: Column(
                children: [
                  // The image takes up the bulk of the tile -- only the
                  // name/checkmark strip below it has a fixed height.
                  Expanded(
                    child: SizedBox(
                      width: double.infinity,
                      child: MediaImage(
                        path: crop.fallbackImageUrl,
                        bucket: 'crop-fallback-images',
                        public: true,
                        placeholder: Container(
                          color: theme.colorScheme.surfaceContainerHigh,
                          alignment: Alignment.center,
                          child: categoryIcon,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 6,
                    ),
                    child: Text(
                      crop.name,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isSelected)
            Positioned(
              top: 4,
              right: 4,
              child: Icon(
                Icons.check_circle,
                size: 18,
                color: theme.colorScheme.primary,
                shadows: const [Shadow(blurRadius: 4, color: Colors.black38)],
              ),
            ),
          // Painted on top so the border is never covered at the
          // rounded corners (the image otherwise sits flush against the
          // top edge with nothing to buffer it).
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: borderRadius,
                  border: Border.all(
                    color: isSelected
                        ? theme.colorScheme.primary
                        : Colors.transparent,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

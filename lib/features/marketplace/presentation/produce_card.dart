import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../core/widgets/media_image.dart';
import '../../../models/marketplace_listing.dart';

/// One produce listing tile in the marketplace grid — image, crop name,
/// and price/kg only (farmer/distance live on the detail screen).
class ProduceCard extends StatelessWidget {
  final MarketplaceListing listing;
  final VoidCallback onTap;

  const ProduceCard({super.key, required this.listing, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderRadius = BorderRadius.circular(14);

    return InkWell(
      onTap: onTap,
      borderRadius: borderRadius,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: borderRadius,
            child: Container(
              color: theme.colorScheme.surfaceContainerLowest,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Square regardless of card width — this is a visual
                  // browse grid, not a data table, so crop name + price
                  // is all the caption needs. The caption below takes
                  // whatever height the grid's aspect ratio leaves over.
                  AspectRatio(
                    aspectRatio: 1,
                    child: MediaImage(
                      path: listing.displayImage.path,
                      bucket: listing.displayImage.bucket,
                      public: listing.displayImage.isFallback,
                      placeholder: Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: Icon(
                          Icons.image_outlined,
                          size: 28,
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            listing.cropName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${'currency_prefix'.tr()} ${listing.pricePerKg.toStringAsFixed(2)}/${'kg'.tr()}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                              height: 1.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Painted on top so the border is never covered at the rounded
          // corners (the image otherwise sits flush against the top edge
          // with nothing to buffer it).
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: borderRadius,
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

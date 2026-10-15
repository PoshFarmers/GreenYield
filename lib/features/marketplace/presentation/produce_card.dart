import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/media_image.dart';
import '../../../models/marketplace_listing.dart';
import '../../pricing/presentation/widgets/market_position_chip.dart';

/// One produce listing tile in the marketplace grid — image, crop name,
/// price/kg, with a small "x% below / above market" indicator pinned to
/// the image's top-right corner when market data exists.
class ProduceCard extends ConsumerWidget {
  final MarketplaceListing listing;
  final VoidCallback onTap;

  const ProduceCard({super.key, required this.listing, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                  AspectRatio(
                    aspectRatio: 1,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        MediaImage(
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
                        Positioned(
                          top: 6,
                          right: 6,
                          child: MarketPositionChip(
                            cropId: listing.cropId,
                            pricePerKg: listing.pricePerKg,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
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

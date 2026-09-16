import 'package:flutter/material.dart';

import '../../../../core/widgets/media_image.dart';
import '../../order_detail_models.dart';

/// One row in the order items list on the detail screen.
/// Shows a product thumbnail, crop name, quantity, unit price,
/// and computed line total.
class OrderItemCard extends StatelessWidget {
  final OrderItemDetail item;

  const OrderItemCard({super.key, required this.item});

  String get _imageBucket {
    final path = item.imageUrl;
    if (path == null) return 'crop-photos';
    if (path.contains('crop-fallback') ||
        path.startsWith('crops/') ||
        !path.contains('/')) {
      return 'crop-fallback-images';
    }
    return 'crop-photos';
  }

  bool get _isPublicImage => _imageBucket == 'crop-fallback-images';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 56,
              height: 56,
              child: item.imageUrl != null
                  ? MediaImage(
                      path: item.imageUrl,
                      bucket: _imageBucket,
                      public: _isPublicImage,
                      placeholder: _placeholder(theme),
                    )
                  : _placeholder(theme),
            ),
          ),
          const SizedBox(width: 12),

          // Name + quantity + price
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.cropName,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${item.quantityKg.toStringAsFixed(0)} kg  '
                  '·  LKR ${item.pricePerKg.toStringAsFixed(2)}/kg',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Line total
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'LKR ${item.lineTotal.toStringAsFixed(2)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'x${item.quantityKg.toStringAsFixed(0)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _placeholder(ThemeData theme) => Container(
    color: theme.colorScheme.surfaceContainerHighest,
    child: Icon(Icons.eco_outlined, size: 24, color: theme.colorScheme.outline),
  );
}

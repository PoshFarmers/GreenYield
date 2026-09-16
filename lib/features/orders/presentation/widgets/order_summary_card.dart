import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/widgets/media_image.dart';
import '../../order_detail_models.dart';
import '../order_detail_screen.dart';
import 'order_status_chip.dart';

class OrderSummaryCard extends StatelessWidget {
  final OrderSummary order;
  final String viewerRole;

  const OrderSummaryCard({
    super.key,
    required this.order,
    required this.viewerRole,
  });

  String get _imageBucket {
    final path = order.firstImageUrl;
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

    // Fallback names
    final cropNameText = order.cropNames.isNotEmpty
        ? order.cropNames.join(', ')
        : 'Order Items';

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              OrderDetailScreen(orderId: order.id, viewerRole: viewerRole),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Top row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.local_shipping_outlined,
                    color: Colors.brown.shade700,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Order ${order.displayId}',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                OrderStatusChip(status: order.status),
              ],
            ),
            const SizedBox(height: 16),

            // Inner card
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.6,
                  ),
                ),
              ),
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Image
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 60,
                      height: 60,
                      child:
                          (order.firstImageUrl != null &&
                              order.firstImageUrl!.isNotEmpty)
                          ? MediaImage(
                              path: order.firstImageUrl!,
                              bucket: _imageBucket,
                              public: _isPublicImage,
                              fit: BoxFit.cover,
                              placeholder: _fallbackImage(theme),
                            )
                          : _fallbackImage(theme),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cropNameText,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          order.totalQuantity > 0
                              ? '${order.totalQuantity.toStringAsFixed(0)} kg'
                              : 'LKR ${order.totalAmount.toStringAsFixed(2)}',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fallbackImage(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.eco_outlined,
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
      ),
    );
  }
}

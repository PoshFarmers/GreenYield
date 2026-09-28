import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../market_overview.dart';

/// Listing price vs. market average. Renders nothing when there is no
/// market average for the crop.
///
/// Compact (default, used on grid tiles): arrow + percentage only,
/// e.g. "↑ 22%". It's overlaid on the tile's photo, so it sits on a
/// near-opaque surface-colored pill to stay readable on any image.
/// [detailed] (listing detail): full phrase ("22% above market") on a
/// tinted pill, the market average and the "based on N orders /
/// estimated" hint.
class MarketPositionChip extends ConsumerWidget {
  final String cropId;
  final double pricePerKg;
  final bool detailed;

  const MarketPositionChip({
    super.key,
    required this.cropId,
    required this.pricePerKg,
    this.detailed = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final market = ref.watch(marketAveragesProvider).asData?.value[cropId];
    final avg = market?.avgPricePerKg;
    if (market == null || avg == null || avg <= 0) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final diff = (pricePerKg - avg) / avg * 100;
    final percent = diff.abs().toStringAsFixed(0);

    final isBelow = diff < -1;
    final isAbove = diff > 1;

    final color = isBelow
        ? scheme.primary
        : isAbove
        ? scheme.error
        : scheme.onSurfaceVariant;
    final icon = isBelow
        ? Icons.arrow_downward
        : isAbove
        ? Icons.arrow_upward
        : Icons.horizontal_rule;

    // Compact tiles only get the number; the full sentence is shown on
    // the listing detail screen.
    final label = !detailed
        ? (isBelow || isAbove ? '$percent%' : '0%')
        : isBelow
        ? 'buyer_market_below'.tr(namedArgs: {'percent': percent})
        : isAbove
        ? 'buyer_market_above'.tr(namedArgs: {'percent': percent})
        : 'buyer_market_at'.tr();

    // Detailed: translucent tint, as before. Compact: the same tint
    // blended over a near-opaque surface so the photo behind it can't
    // wash out the text.
    final background = detailed
        ? color.withValues(alpha: 0.12)
        : Color.alphaBlend(
            color.withValues(alpha: 0.12),
            scheme.surface.withValues(alpha: 0.92),
          );

    final chip = Container(
      padding: EdgeInsets.symmetric(horizontal: detailed ? 8 : 6, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(detailed ? 20 : 8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: detailed ? 14 : 11, color: color),
          const SizedBox(width: 2),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  (detailed
                          ? theme.textTheme.labelMedium
                          : theme.textTheme.labelSmall?.copyWith(fontSize: 11))
                      ?.copyWith(color: color, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (!detailed) return chip;

    final hint = market.source == 'orders'
        ? 'market_based_on_orders'.tr(
            namedArgs: {'count': '${market.sampleSize}'},
          )
        : 'market_estimated'.tr();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        chip,
        const SizedBox(height: 2),
        Text(
          'buyer_market_average'.tr(
            namedArgs: {'amount': 'LKR ${NumberFormat('#,##0').format(avg)}'},
          ),
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        Text(
          hint,
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../models/market_price.dart';
import '../../../../models/price_trend.dart';
import '../../market_price_service.dart';

/// shows a farmer's asking price for a crop against
/// the live market average and (if available) its 7-day trend. Falls
/// back to a neutral "not enough data yet" state for crops with no
/// completed-order history.
class MarketPriceComparisonCard extends StatefulWidget {
  final String cropId;
  final double farmerPricePerKg;

  /// When true, renders as a compact single line suitable for a
  /// listing card rather than the full multi-line block used on the
  /// price-setting step. Defaults to false.
  final bool compact;

  const MarketPriceComparisonCard({
    super.key,
    required this.cropId,
    required this.farmerPricePerKg,
    this.compact = false,
  });

  @override
  State<MarketPriceComparisonCard> createState() =>
      _MarketPriceComparisonCardState();
}

class _MarketPriceComparisonCardState extends State<MarketPriceComparisonCard> {
  final _service = const MarketPriceService();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return StreamBuilder<MarketPrice?>(
      stream: _service.watchForCrop(widget.cropId),
      builder: (context, marketSnapshot) {
        final market = marketSnapshot.data;
        if (market == null || market.avgPricePerKg == null) {
          if (widget.compact) return const SizedBox.shrink();
          return _shell(
            theme,
            child: Row(
              children: [
                Icon(
                  Icons.query_stats,
                  size: 18,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'market_average_unavailable'.tr(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        final avg = market.avgPricePerKg!;
        final diffPercent = avg == 0
            ? 0.0
            : ((widget.farmerPricePerKg - avg) / avg) * 100;
        final isAbove = diffPercent > 0.5;
        final isBelow = diffPercent < -0.5;

        if (widget.compact) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isAbove
                    ? Icons.arrow_upward
                    : isBelow
                    ? Icons.arrow_downward
                    : Icons.horizontal_rule,
                size: 12,
                color: isAbove
                    ? theme.colorScheme.error
                    : isBelow
                    ? Colors.green
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 2),
              Text(
                isAbove || isBelow
                    ? '${diffPercent.abs().toStringAsFixed(0)}% ${'vs_market'.tr()}'
                    : 'at_market'.tr(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          );
        }

        return StreamBuilder<PriceTrend?>(
          stream: _service.watchTrendForCrop(widget.cropId),
          builder: (context, trendSnapshot) {
            final trend = trendSnapshot.data;

            return _shell(
              theme,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.query_stats,
                        size: 18,
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'market_average_label'.tr(),
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Rs ${avg.toStringAsFixed(0)}',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isAbove
                        ? 'price_comparison_above'.tr(
                            namedArgs: {
                              'percent': diffPercent.abs().toStringAsFixed(0),
                            },
                          )
                        : isBelow
                        ? 'price_comparison_below'.tr(
                            namedArgs: {
                              'percent': diffPercent.abs().toStringAsFixed(0),
                            },
                          )
                        : 'price_comparison_at_market'.tr(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                  if (trend != null && trend.changePercent != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          switch (trend.direction) {
                            PriceTrendDirection.up => Icons.trending_up,
                            PriceTrendDirection.down => Icons.trending_down,
                            PriceTrendDirection.stable => Icons.trending_flat,
                          },
                          size: 16,
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'price_trend_hint'.tr(
                            namedArgs: {
                              'percent': trend.changePercent!
                                  .abs()
                                  .toStringAsFixed(0),
                              'days': '${trend.periodDays}',
                            },
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSecondaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _shell(ThemeData theme, {required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}

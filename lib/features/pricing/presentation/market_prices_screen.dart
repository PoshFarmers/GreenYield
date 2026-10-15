import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/widgets/app_secondary_header.dart';
import '../../../core/widgets/media_image.dart';
import '../market_overview.dart';
import 'widgets/price_history_chart.dart';

String _lkr(num v) => 'LKR ${NumberFormat('#,##0.00').format(v)}';

String _hint(MarketOverviewRow r) => r.source == 'orders'
    ? 'market_based_on_orders'.tr(namedArgs: {'count': '${r.sampleSize}'})
    : 'market_estimated'.tr();

/// Buyer-facing market overview: every crop with average, min/max, trend and a
/// 30-day sparkline. Tap a crop for the full price history chart.
class MarketPricesScreen extends StatefulWidget {
  const MarketPricesScreen({super.key});

  @override
  State<MarketPricesScreen> createState() => _MarketPricesScreenState();
}

class _MarketPricesScreenState extends State<MarketPricesScreen> {
  late final Stream<List<MarketOverviewRow>> _rows;
  late final Stream<Map<String, List<double>>> _spark;

  @override
  void initState() {
    super.initState();
    const service = MarketOverviewService();
    _rows = service.watchOverview();
    _spark = service.watchSparklines();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppSecondaryHeader(title: 'buyer_market_title'.tr()),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: StreamBuilder<List<MarketOverviewRow>>(
              stream: _rows,
              builder: (context, rowsSnap) {
                if (!rowsSnap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final rows = rowsSnap.data!;
                if (rows.isEmpty) {
                  return Center(
                    child: Text(
                      'buyer_market_empty'.tr(),
                      style: theme.textTheme.bodyMedium,
                    ),
                  );
                }
                return StreamBuilder<Map<String, List<double>>>(
                  stream: _spark,
                  builder: (context, sparkSnap) {
                    final spark = sparkSnap.data ?? const {};
                    return ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) => _MarketRow(
                        row: rows[i],
                        spark: spark[rows[i].cropId] ?? const [],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _MarketRow extends StatelessWidget {
  final MarketOverviewRow row;
  final List<double> spark;

  const _MarketRow({required this.row, required this.spark});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasData = row.avg != null;
    final pct = row.changePercent;
    final (trendIcon, trendColor) = switch (row.trendDirection) {
      'up' => (Icons.trending_up, scheme.primary),
      'down' => (Icons.trending_down, scheme.error),
      _ => (Icons.trending_flat, scheme.onSurfaceVariant),
    };

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => _CropMarketScreen(row: row))),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 48,
                height: 48,
                child: MediaImage(
                  path: row.fallbackImageUrl,
                  bucket: 'crop-fallback-images',
                  public: true,
                  placeholder: Icon(Icons.eco, color: scheme.primary),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (hasData) ...[
                    Text(
                      '${_lkr(row.avg!)} / ${'kg'.tr()}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (row.min != null && row.max != null)
                      Text(
                        'buyer_market_range'.tr(
                          namedArgs: {
                            'min': NumberFormat('#,##0').format(row.min),
                            'max': NumberFormat('#,##0').format(row.max),
                          },
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    Text(
                      _hint(row),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ] else
                    Text(
                      'buyer_market_no_data'.tr(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _Sparkline(values: spark, color: trendColor),
                const SizedBox(height: 4),
                if (hasData)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(trendIcon, size: 16, color: trendColor),
                      if (pct != null) ...[
                        const SizedBox(width: 2),
                        Text(
                          '${pct.abs().toStringAsFixed(1)}%',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: trendColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Sparkline extends StatelessWidget {
  final List<double> values;
  final Color color;

  const _Sparkline({required this.values, required this.color});

  @override
  Widget build(BuildContext context) {
    const w = 64.0, h = 28.0;
    if (values.length < 2) return const SizedBox(width: w, height: h);
    final lo = values.reduce(math.min);
    final hi = values.reduce(math.max);
    final pad = hi - lo == 0 ? 1.0 : (hi - lo) * 0.1;
    return SizedBox(
      width: w,
      height: h,
      child: LineChart(
        LineChartData(
          minY: lo - pad,
          maxY: hi + pad,
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < values.length; i++)
                  FlSpot(i.toDouble(), values[i]),
              ],
              isCurved: false,
              barWidth: 1.5,
              color: color,
              dotData: const FlDotData(show: false),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full history for one crop, reusing the shared [PriceHistoryChart].
class _CropMarketScreen extends StatelessWidget {
  final MarketOverviewRow row;

  const _CropMarketScreen({required this.row});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppSecondaryHeader(title: row.name),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (row.min != null && row.max != null) ...[
                  Text(
                    'buyer_market_range'.tr(
                      namedArgs: {'min': _lkr(row.min!), 'max': _lkr(row.max!)},
                    ),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                PriceHistoryChart(cropId: row.cropId),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

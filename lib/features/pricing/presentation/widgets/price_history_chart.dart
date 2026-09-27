import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../models/market_price.dart';
import '../../../../models/price_history.dart';
import '../../../../models/price_trend.dart';
import '../../market_price_service.dart';

enum PriceRange {
  d7(7, 'price_range_7d', 2),
  d30(30, 'price_range_30d', 7),
  d90(90, 'price_range_90d', 15);

  final int days;
  final String labelKey;

  /// X-axis label every N days.
  final int labelEvery;

  const PriceRange(this.days, this.labelKey, this.labelEvery);
}

/// Reusable price history for one crop: header (market average, trend chip,
/// change over the range), 7D/30D/90D toggle, date-based line chart with a
/// min/max band, touch tooltip and optional dashed overlay lines.
///
/// Missing days: the line joins days that have data and dots mark real order
/// days; no points are invented. Stream-based, works offline.
class PriceHistoryChart extends StatefulWidget {
  final String cropId;

  /// Farmer's own current listing price (dashed overlay), if any.
  final double? ownPricePerKg;

  final PriceRange initialRange;

  /// Called when the user picks a different range.
  final ValueChanged<PriceRange>? onRangeChanged;

  const PriceHistoryChart({
    super.key,
    required this.cropId,
    this.ownPricePerKg,

    this.initialRange = PriceRange.d30,
    this.onRangeChanged,
  });

  @override
  State<PriceHistoryChart> createState() => _PriceHistoryChartState();
}

class _PriceHistoryChartState extends State<PriceHistoryChart> {
  final _service = const MarketPriceService();

  late PriceRange _range;
  late DateTime _start; // UTC date-only, first day of the range
  late Stream<List<PriceHistory>> _history;
  late Stream<MarketPrice?> _market;
  late Stream<PriceTrend?> _trend;

  @override
  void initState() {
    super.initState();
    _range = widget.initialRange;
    _bindCrop();
  }

  @override
  void didUpdateWidget(covariant PriceHistoryChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cropId != widget.cropId) _bindCrop();
  }

  void _bindCrop() {
    _market = _service.watchForCrop(widget.cropId);
    _trend = _service.watchTrendForCrop(widget.cropId);
    _bindHistory();
  }

  void _bindHistory() {
    final now = DateTime.now();
    final today = DateTime.utc(now.year, now.month, now.day);
    _start = today.subtract(Duration(days: _range.days - 1));
    _history = _service.watchHistory(widget.cropId, from: _start);
  }

  int _dayIndex(PriceHistory r) => DateTime.utc(
    r.priceDate.year,
    r.priceDate.month,
    r.priceDate.day,
  ).difference(_start).inDays;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<List<PriceHistory>>(
      stream: _history,
      builder: (context, snapshot) {
        final rows = [
          for (final r in snapshot.data ?? const <PriceHistory>[])
            if (_dayIndex(r) >= 0 && _dayIndex(r) < _range.days) r,
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(theme, rows),
            const SizedBox(height: 12),
            SegmentedButton<PriceRange>(
              segments: [
                for (final r in PriceRange.values)
                  ButtonSegment(value: r, label: Text(r.labelKey.tr())),
              ],
              selected: {_range},
              showSelectedIcon: false,
              onSelectionChanged: (s) {
                setState(() {
                  _range = s.first;
                  _bindHistory();
                });
                widget.onRangeChanged?.call(s.first);
              },
            ),
            const SizedBox(height: 12),
            SizedBox(height: 220, child: _body(theme, snapshot, rows)),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------- header

  Widget _header(ThemeData theme, List<PriceHistory> rows) {
    double? change;
    if (rows.length >= 2 && rows.first.avgPricePerKg > 0) {
      change =
          (rows.last.avgPricePerKg - rows.first.avgPricePerKg) /
          rows.first.avgPricePerKg *
          100;
    }
    final money = NumberFormat('#,##0.00');

    return StreamBuilder<MarketPrice?>(
      stream: _market,
      builder: (context, marketSnap) {
        final market = marketSnap.data;
        final avg = market?.avgPricePerKg;
        return StreamBuilder<PriceTrend?>(
          stream: _trend,
          builder: (context, trendSnap) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'price_current_avg'.tr(),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        avg == null ? '—' : 'LKR ${money.format(avg)}',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (market != null && avg != null)
                        Text(
                          market.source == 'orders'
                              ? 'market_based_on_orders'.tr(
                                  namedArgs: {'count': '${market.sampleSize}'},
                                )
                              : 'market_estimated'.tr(),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _trendChip(theme, trendSnap.data),
                    if (change != null) ...[
                      const SizedBox(height: 4),
                      _changeChip(theme, change),
                    ],
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _chip(ThemeData theme, IconData icon, Color color, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _trendChip(ThemeData theme, PriceTrend? trend) {
    final scheme = theme.colorScheme;
    if (trend == null || trend.changePercent == null) {
      return _chip(
        theme,
        Icons.trending_flat,
        scheme.onSurfaceVariant,
        'price_trend_unknown'.tr(),
      );
    }
    final pct = '${trend.changePercent!.abs().toStringAsFixed(1)}%';
    return switch (trend.direction) {
      PriceTrendDirection.up => _chip(
        theme,
        Icons.trending_up,
        scheme.primary,
        '${'price_trend_up'.tr()} $pct',
      ),
      PriceTrendDirection.down => _chip(
        theme,
        Icons.trending_down,
        scheme.error,
        '${'price_trend_down'.tr()} $pct',
      ),
      PriceTrendDirection.stable => _chip(
        theme,
        Icons.trending_flat,
        scheme.onSurfaceVariant,
        'price_trend_stable'.tr(),
      ),
    };
  }

  Widget _changeChip(ThemeData theme, double change) {
    final scheme = theme.colorScheme;
    final color = change > 0.5
        ? scheme.primary
        : change < -0.5
        ? scheme.error
        : scheme.onSurfaceVariant;
    final signed = '${change >= 0 ? '+' : ''}${change.toStringAsFixed(1)}';
    return _chip(
      theme,
      change >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
      color,
      'price_change_over_range'.tr(
        namedArgs: {'percent': signed, 'days': '${_range.days}'},
      ),
    );
  }

  // ------------------------------------------------------------------ body

  Widget _body(
    ThemeData theme,
    AsyncSnapshot<List<PriceHistory>> snap,
    List<PriceHistory> rows,
  ) {
    if (snap.hasError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('price_chart_error'.tr(), style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => setState(_bindHistory),
              icon: const Icon(Icons.refresh),
              label: Text('retry'.tr()),
            ),
          ],
        ),
      );
    }
    if (!snap.hasData) return const Center(child: CircularProgressIndicator());
    if (rows.isEmpty) {
      return Center(
        child: Text(
          'price_chart_empty'.tr(),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
      );
    }
    return _chart(theme, rows);
  }

  static double _niceInterval(double raw) {
    if (raw <= 0) return 1;
    final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final res = raw / mag;
    final nice = res <= 1
        ? 1
        : res <= 2
        ? 2
        : res <= 5
        ? 5
        : 10;
    return nice * mag;
  }

  Widget _chart(ThemeData theme, List<PriceHistory> rows) {
    final scheme = theme.colorScheme;
    final byX = {for (final r in rows) _dayIndex(r): r};
    List<FlSpot> spots(double Function(PriceHistory) f) => [
      for (final r in rows) FlSpot(_dayIndex(r).toDouble(), f(r)),
    ];

    var lo = rows.map((r) => r.minPricePerKg).reduce(math.min);
    var hi = rows.map((r) => r.maxPricePerKg).reduce(math.max);
    for (final v in [widget.ownPricePerKg]) {
      if (v != null) {
        lo = math.min(lo, v);
        hi = math.max(hi, v);
      }
    }
    final span = hi - lo;
    final pad = span > 0 ? span * 0.12 : math.max(hi * 0.1, 5.0);
    final interval = _niceInterval((span + 2 * pad) / 4);
    final minY = math.max(
      0.0,
      ((lo - pad) / interval).floorToDouble() * interval,
    );
    final maxY = ((hi + pad) / interval).ceilToDouble() * interval;

    final locale = context.locale.toString();
    final dateFmt = DateFormat.MMMd(locale);
    final axisFmt = NumberFormat('#,##0');
    final moneyFmt = NumberFormat('#,##0.00');
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    final mainBar = LineChartBarData(
      spots: spots((r) => r.avgPricePerKg),
      color: scheme.primary,
      barWidth: 2.5,
      isCurved: false,
      dotData: FlDotData(
        show: true,
        getDotPainter: (spot, percent, bar, index) {
          final synthetic = byX[spot.x.toInt()]?.isSynthetic ?? true;
          return FlDotCirclePainter(
            radius: synthetic ? 0 : 3.5,
            color: scheme.primary,
            strokeWidth: 0,
          );
        },
      ),
    );
    LineChartBarData bandLine(double Function(PriceHistory) f) =>
        LineChartBarData(
          spots: spots(f),
          color: scheme.primary.withValues(alpha: 0.3),
          barWidth: 1,
          isCurved: false,
          dotData: const FlDotData(show: false),
        );

    HorizontalLine overlay(
      double y,
      Color color,
      String labelKey,
      Alignment alignment,
    ) => HorizontalLine(
      y: y,
      color: color,
      strokeWidth: 1.5,
      dashArray: [6, 4],
      label: HorizontalLineLabel(
        show: true,
        alignment: alignment,
        style: theme.textTheme.labelSmall?.copyWith(color: color),
        labelResolver: (_) => labelKey.tr(),
      ),
    );

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (_range.days - 1).toDouble(),
        minY: minY,
        maxY: maxY,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: scheme.outlineVariant, strokeWidth: 0.5),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              interval: interval,
              getTitlesWidget: (value, meta) => SideTitleWidget(
                meta: meta,
                child: Text(axisFmt.format(value), style: labelStyle),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: _range.labelEvery.toDouble(),
              getTitlesWidget: (value, meta) {
                if (value.round() % _range.labelEvery != 0) {
                  return const SizedBox.shrink();
                }
                final d = _start.add(Duration(days: value.round()));
                return SideTitleWidget(
                  meta: meta,
                  child: Text(dateFmt.format(d), style: labelStyle),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          mainBar,
          bandLine((r) => r.minPricePerKg),
          bandLine((r) => r.maxPricePerKg),
        ],
        betweenBarsData: [
          BetweenBarsData(
            fromIndex: 1,
            toIndex: 2,
            color: scheme.primary.withValues(alpha: 0.12),
          ),
        ],
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            if (widget.ownPricePerKg != null)
              overlay(
                widget.ownPricePerKg!,
                scheme.tertiary,
                'price_your_listing_price',
                Alignment.topRight,
              ),
          ],
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => scheme.inverseSurface,
            getTooltipItems: (touched) => touched.map((s) {
              if (s.barIndex != 0) return null;
              final r = byX[s.x.toInt()];
              if (r == null) return null;
              final d = _start.add(Duration(days: s.x.toInt()));
              final base = TextStyle(
                color: scheme.onInverseSurface,
                fontSize: 12,
              );
              final lines = <String>[
                '${'price_tooltip_avg'.tr()}: LKR ${moneyFmt.format(r.avgPricePerKg)}',
                '${'price_tooltip_min_max'.tr()}: ${moneyFmt.format(r.minPricePerKg)} – ${moneyFmt.format(r.maxPricePerKg)}',
                r.isSynthetic
                    ? 'price_tooltip_estimated'.tr()
                    : 'price_tooltip_orders'.tr(
                        namedArgs: {
                          'count': '${r.orderCount}',
                          'kg': r.totalQuantityKg.toStringAsFixed(0),
                        },
                      ),
              ];
              return LineTooltipItem(
                '${dateFmt.format(d)}\n',
                base.copyWith(fontWeight: FontWeight.bold),
                children: [TextSpan(text: lines.join('\n'), style: base)],
              );
            }).toList(),
          ),
          getTouchedSpotIndicator: (bar, indexes) => indexes
              .map(
                (_) => identical(bar, mainBar)
                    ? TouchedSpotIndicatorData(
                        FlLine(
                          color: scheme.primary.withValues(alpha: 0.4),
                          strokeWidth: 1,
                        ),
                        const FlDotData(show: true),
                      )
                    : const TouchedSpotIndicatorData(
                        FlLine(color: Colors.transparent),
                        FlDotData(show: false),
                      ),
              )
              .toList(),
        ),
      ),
    );
  }
}

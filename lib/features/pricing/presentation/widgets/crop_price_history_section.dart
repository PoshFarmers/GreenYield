import 'package:easy_localization/easy_localization.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../models/farmer_profile.dart';
import '../../../../models/price_history.dart';
import '../../market_price_service.dart';

/// Crop-picker + line chart of the last 30 days of `price_history`
/// for the selected crop.
class CropPriceHistorySection extends StatefulWidget {
  final List<FarmerCrop> crops;

  const CropPriceHistorySection({super.key, required this.crops});

  @override
  State<CropPriceHistorySection> createState() =>
      _CropPriceHistorySectionState();
}

class _CropPriceHistorySectionState extends State<CropPriceHistorySection> {
  final _service = const MarketPriceService();
  String? _selectedCropId;
  List<PriceHistory>? _history;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.crops.isNotEmpty) {
      _selectedCropId = widget.crops.first.cropId;
      _load();
    }
  }

  @override
  void didUpdateWidget(covariant CropPriceHistorySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.crops.isEmpty) {
      if (_selectedCropId != null || _history != null) {
        setState(() {
          _selectedCropId = null;
          _history = null;
        });
      }
      return;
    }

    final selectedCropStillExists = widget.crops.any(
      (crop) => crop.cropId == _selectedCropId,
    );
    if (!selectedCropStillExists) {
      _selectedCropId = widget.crops.first.cropId;
      _load();
    }
  }

  Future<void> _load() async {
    final cropId = _selectedCropId;
    if (cropId == null) return;
    setState(() => _isLoading = true);
    final history = await _service.getRecentHistory(cropId, limit: 30);
    if (!mounted) return;
    setState(() {
      // API returns newest-first; the chart wants oldest-first.
      _history = history.reversed.toList();
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (widget.crops.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(child: Text('select_crop_for_history'.tr())),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'price_history_title'.tr(),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButton<String>(
          value: _selectedCropId,
          isExpanded: true,
          items: widget.crops
              .map(
                (c) =>
                    DropdownMenuItem(value: c.cropId, child: Text(c.cropName)),
              )
              .toList(),
          onChanged: (value) {
            setState(() => _selectedCropId = value);
            _load();
          },
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 180,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : (_history == null || _history!.length < 2)
              ? Center(
                  child: Text(
                    'no_price_history_yet'.tr(),
                    style: theme.textTheme.bodySmall,
                  ),
                )
              : LineChart(
                  LineChartData(
                    gridData: const FlGridData(show: false),
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 44,
                          getTitlesWidget: (value, meta) => Text(
                            value.toStringAsFixed(0),
                            style: theme.textTheme.labelSmall,
                          ),
                        ),
                      ),
                      bottomTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [
                      LineChartBarData(
                        isCurved: true,
                        color: theme.colorScheme.primary,
                        barWidth: 3,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.12,
                          ),
                        ),
                        spots: [
                          for (var i = 0; i < _history!.length; i++)
                            FlSpot(i.toDouble(), _history![i].avgPricePerKg),
                        ],
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

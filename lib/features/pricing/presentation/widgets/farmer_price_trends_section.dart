import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../models/farmer_profile.dart';
import '../../../../models/market_price.dart';
import '../../../../models/price_trend.dart';
import '../../../profile/farmer/farmer_profile_service.dart';
import '../../market_price_service.dart';

class FarmerPriceTrendsSection extends StatefulWidget {
  final String farmerProfileId;

  const FarmerPriceTrendsSection({super.key, required this.farmerProfileId});

  @override
  State<FarmerPriceTrendsSection> createState() =>
      _FarmerPriceTrendsSectionState();
}

class _FarmerPriceTrendsSectionState extends State<FarmerPriceTrendsSection> {
  final _farmerService = FarmerProfileService();
  final _marketService = const MarketPriceService();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return StreamBuilder<FarmerProfile?>(
      stream: _farmerService.watchOwnProfile(widget.farmerProfileId),
      builder: (context, farmerSnapshot) {
        final crops = farmerSnapshot.data?.crops ?? [];
        if (crops.isEmpty) return const SizedBox.shrink();

        final cropIds = crops.map((c) => c.cropId).toList();

        return StreamBuilder<Map<String, MarketPrice>>(
          stream: _marketService.watchForCrops(cropIds),
          builder: (context, pricesSnapshot) {
            final prices = pricesSnapshot.data ?? const {};

            return StreamBuilder<Map<String, PriceTrend>>(
              stream: _marketService.watchTrendsForCrops(cropIds),
              builder: (context, trendsSnapshot) {
                final trends = trendsSnapshot.data ?? const {};

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'market_prices_title'.tr(),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'market_prices_subtitle'.tr(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 96,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: crops.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 10),
                        itemBuilder: (context, index) {
                          final crop = crops[index];
                          return _CropPriceTile(
                            cropName: crop.cropName,
                            price: prices[crop.cropId],
                            trend: trends[crop.cropId],
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

class _CropPriceTile extends StatelessWidget {
  final String cropName;
  final MarketPrice? price;
  final PriceTrend? trend;

  const _CropPriceTile({
    required this.cropName,
    required this.price,
    required this.trend,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final avg = price?.avgPricePerKg;

    return Container(
      width: 140,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            cropName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            avg == null ? '—' : 'Rs ${avg.toStringAsFixed(0)}',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: avg == null
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 2),
          if (avg == null)
            Text(
              'no_market_data_short'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else if (trend != null && trend!.changePercent != null)
            Row(
              children: [
                Icon(
                  switch (trend!.direction) {
                    PriceTrendDirection.up => Icons.trending_up,
                    PriceTrendDirection.down => Icons.trending_down,
                    PriceTrendDirection.stable => Icons.trending_flat,
                  },
                  size: 14,
                  color: switch (trend!.direction) {
                    PriceTrendDirection.up => Colors.green,
                    PriceTrendDirection.down => theme.colorScheme.error,
                    PriceTrendDirection.stable =>
                      theme.colorScheme.onSurfaceVariant,
                  },
                ),
                const SizedBox(width: 2),
                Text(
                  '${trend!.changePercent!.abs().toStringAsFixed(0)}%',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            )
          else
            Text(
              'per_kg'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

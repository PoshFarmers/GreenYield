import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/widgets/media_image.dart';
import '../../../../models/farmer_profile.dart';
import '../../../../models/produce_listing.dart';
import '../../../listings/produce_listing_service.dart';
import 'price_history_chart.dart';

/// Farmer home: crop chips (with images) + [PriceHistoryChart] for the
/// selected crop, with the farmer's own active listing price and default price
/// as dashed overlays.
class CropPriceHistorySection extends StatefulWidget {
  final String farmerProfileId;
  final List<FarmerCrop> crops;

  const CropPriceHistorySection({
    super.key,
    required this.farmerProfileId,
    required this.crops,
  });

  @override
  State<CropPriceHistorySection> createState() =>
      _CropPriceHistorySectionState();
}

class _CropPriceHistorySectionState extends State<CropPriceHistorySection> {
  String? _selectedCropId;

  @override
  void initState() {
    super.initState();
    _selectedCropId = widget.crops.firstOrNull?.cropId;
  }

  @override
  void didUpdateWidget(covariant CropPriceHistorySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.crops.any((c) => c.cropId == _selectedCropId)) {
      _selectedCropId = widget.crops.firstOrNull?.cropId;
    }
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

    final selected = widget.crops.firstWhere(
      (c) => c.cropId == _selectedCropId,
      orElse: () => widget.crops.first,
    );

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
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final c in widget.crops)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    showCheckmark: false,
                    avatar: ClipOval(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: MediaImage(
                          path: c.displayImage.path,
                          bucket: c.displayImage.bucket,
                          public: c.displayImage.isFallback,
                          placeholder: Icon(
                            Icons.eco,
                            size: 16,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                    label: Text(c.cropName),
                    selected: c.cropId == selected.cropId,
                    onSelected: (_) =>
                        setState(() => _selectedCropId = c.cropId),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _ChartWithOverlay(
          key: ValueKey(selected.cropId),
          farmerProfileId: widget.farmerProfileId,
          crop: selected,
        ),
      ],
    );
  }
}

/// Owns the own-listings stream (created per State, so remounting never
/// re-listens to a consumed PowerSync watch stream).
class _ChartWithOverlay extends StatefulWidget {
  final String farmerProfileId;
  final FarmerCrop crop;

  const _ChartWithOverlay({
    super.key,
    required this.farmerProfileId,
    required this.crop,
  });

  @override
  State<_ChartWithOverlay> createState() => _ChartWithOverlayState();
}

class _ChartWithOverlayState extends State<_ChartWithOverlay> {
  late final Stream<List<ProduceListing>> _listings;

  @override
  void initState() {
    super.initState();
    _listings = ProduceListingService().watchOwnListings(
      widget.farmerProfileId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ProduceListing>>(
      stream: _listings,
      builder: (context, snapshot) {
        double? own;
        for (final l in snapshot.data ?? const <ProduceListing>[]) {
          if (l.cropId == widget.crop.cropId && l.status == 'active') {
            own = l.pricePerKg;
            break;
          }
        }
        return PriceHistoryChart(
          cropId: widget.crop.cropId,
          ownPricePerKg: own,
          defaultPricePerKg: widget.crop.defaultPricePerKg,
        );
      },
    );
  }
}

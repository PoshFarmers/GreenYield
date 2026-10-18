import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../models/farmer_profile.dart';
import '../../assistant/listing_assistant.dart';

/// What the farmer confirmed in the sheet.
typedef SnapResult = ({FarmerCrop crop, String description});

/// Snap-to-List: shows the photo, asks the assistant for a suggestion,
/// then lets the farmer correct the crop and description before using
/// them. Nothing is applied without "Use these". Pops with a
/// [SnapResult], or null if dismissed.
class SnapToListSheet extends StatefulWidget {
  final Uint8List imageBytes;
  final List<FarmerCrop> crops;
  final ListingAssistant assistant;
  final String languageCode;

  const SnapToListSheet({
    super.key,
    required this.imageBytes,
    required this.crops,
    required this.assistant,
    required this.languageCode,
  });

  static Future<SnapResult?> show(
    BuildContext context, {
    required Uint8List imageBytes,
    required List<FarmerCrop> crops,
    required ListingAssistant assistant,
  }) {
    return showModalBottomSheet<SnapResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => SnapToListSheet(
        imageBytes: imageBytes,
        crops: crops,
        assistant: assistant,
        languageCode: context.locale.languageCode,
      ),
    );
  }

  @override
  State<SnapToListSheet> createState() => _SnapToListSheetState();
}

class _SnapToListSheetState extends State<SnapToListSheet> {
  final _descriptionController = TextEditingController();
  ListingSuggestion? _suggestion;
  FarmerCrop? _crop;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    // FallbackListingAssistant never throws — worst case it's a sample.
    final suggestion = await widget.assistant.suggest(
      widget.imageBytes,
      languageCode: widget.languageCode,
      crops: widget.crops,
    );
    if (!mounted) return;
    setState(() {
      _suggestion = suggestion;
      // An unsure AI match isn't preselected: the farmer must choose.
      final preselect =
          suggestion.isConfident ||
          suggestion.source == SuggestionSource.sample;
      _crop = preselect
          ? widget.crops.where((c) => c.cropId == suggestion.cropId).firstOrNull
          : null;
      _descriptionController.text = suggestion.description;
    });
  }

  String _reasonText(String? reason) => switch (reason) {
    'disabled' => 'snap_reason_disabled'.tr(),
    'offline' => 'snap_reason_offline'.tr(),
    'cooldown' => 'snap_reason_cooldown'.tr(),
    'daily_cap' => 'snap_reason_daily_cap'.tr(),
    'image_too_large' => 'snap_reason_too_large'.tr(),
    _ => 'snap_reason_unavailable'.tr(),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final suggestion = _suggestion;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'snap_card_title'.tr(),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                height: 170,
                child: Image.memory(widget.imageBytes, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(height: 16),
            if (suggestion == null)
              _buildLoading(theme)
            else
              ..._buildResult(theme, suggestion),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Text('snap_analyzing'.tr(), style: theme.textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: const LinearProgressIndicator(minHeight: 6),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildResult(ThemeData theme, ListingSuggestion suggestion) {
    final isAi = suggestion.isAiGenerated;
    final scheme = theme.colorScheme;
    final suggestedCrop = widget.crops
        .where((c) => c.cropId == suggestion.cropId)
        .firstOrNull;

    return [
      // Honest labelling: AI output vs a sample that ignores the photo.
      Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: (isAi ? scheme.primary : scheme.outline).withValues(
              alpha: 0.12,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isAi ? Icons.auto_awesome : Icons.science_outlined,
                size: 16,
                color: isAi ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                (isAi ? 'snap_badge_ai' : 'snap_badge_sample').tr(),
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: isAi ? scheme.primary : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
      if (!isAi) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${_reasonText(suggestion.fallbackReason)} '
                  '${'snap_sample_note'.tr()}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 16),
      Text('snap_crop_label'.tr(), style: theme.textTheme.labelLarge),
      const SizedBox(height: 4),
      if (isAi)
        Text(
          !suggestion.isConfident || suggestedCrop == null
              ? 'snap_pick_crop'.tr()
              : (suggestion.confidence >= 0.8
                        ? 'snap_confidence_high'
                        : 'snap_confidence_medium')
                    .tr(namedArgs: {'crop': suggestedCrop.cropName}),
          style: theme.textTheme.bodySmall?.copyWith(
            color: suggestion.isConfident ? null : scheme.error,
          ),
        ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final crop in widget.crops)
            ChoiceChip(
              label: Text(crop.cropName),
              selected: _crop?.cropId == crop.cropId,
              onSelected: (_) => setState(() => _crop = crop),
            ),
        ],
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _descriptionController,
        minLines: 2,
        maxLines: 4,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: 'snap_description_label'.tr(),
          helperText: isAi ? 'snap_description_helper'.tr() : null,
          alignLabelWithHint: true,
        ),
      ),
      const SizedBox(height: 20),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('snap_dismiss'.tr()),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: _crop == null
                  ? null
                  : () => Navigator.of(context).pop<SnapResult>((
                      crop: _crop!,
                      description: _descriptionController.text.trim(),
                    )),
              child: Text('snap_use'.tr()),
            ),
          ),
        ],
      ),
    ];
  }
}

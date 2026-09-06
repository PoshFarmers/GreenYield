import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../core/storage/crop_photo_service.dart';
import '../../../core/widgets/app_secondary_header.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/image_source_sheet.dart';
import '../../../core/widgets/media_image.dart';
import '../../../models/farmer_profile.dart';
import '../../../models/profile.dart';
import '../../pricing/presentation/widgets/market_price_comparison_card.dart';
import '../../profile/farmer/crop_price_bounds.dart';
import '../../profile/farmer/farmer_profile_service.dart';
import '../produce_listing_service.dart';

/// Multi-step "post produce for sale" flow — writes one `produce_listing`
/// row (see CROP_AND_LISTING_DESIGN.md §2 step 3). The crop must already
/// be on the farmer's `farmer_crop` menu; description/price/photo all
/// pre-fill from it and can be overridden per batch.
class AddHarvestScreen extends ConsumerStatefulWidget {
  final Profile profile;

  const AddHarvestScreen({super.key, required this.profile});

  @override
  ConsumerState<AddHarvestScreen> createState() => _AddHarvestScreenState();
}

class _AddHarvestScreenState extends ConsumerState<AddHarvestScreen> {
  static const _stepCount = 4;

  final _farmerService = FarmerProfileService();
  final _listingService = ProduceListingService();

  final _quantityController = TextEditingController();
  final _priceController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _searchController = TextEditingController();

  late final Stream<FarmerProfile?> _farmerProfileStream;

  int _step = 0;
  String _search = '';
  FarmerCrop? _crop;
  DateTime? _harvestedOn;
  Uint8List? _photoBytes;
  String? _photoFileName;
  bool _isPublishing = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Broadcast: the crop-selection step's StreamBuilder is unmounted and
    // remounted each time the wizard steps away from and back to step 0,
    // which would otherwise re-listen to an already-consumed single-
    // subscription PowerSync watch stream ("Bad state: Stream has already
    // been listened to").
    _farmerProfileStream = _farmerService
        .watchOwnProfile(widget.profile.id)
        .asBroadcastStream();
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _priceController.dispose();
    _descriptionController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  double get _quantity => double.tryParse(_quantityController.text) ?? 0;
  double get _price => double.tryParse(_priceController.text) ?? 0;

  ({double min, double max}) get _bounds =>
      priceBoundsFor(_crop?.cropName ?? '');

  void _selectCrop(FarmerCrop crop) {
    setState(() {
      _crop = crop;
      _descriptionController.text = crop.description ?? '';
      _priceController.text = (crop.defaultPricePerKg ?? _bounds.min)
          .toStringAsFixed(0);
    });
  }

  /// Bounds are re-checked here (not just trusted from crop setup)
  /// because the allowed range can change between then and now.
  String? get _blockingError {
    switch (_step) {
      case 0:
        return _crop == null ? 'error_select_a_crop'.tr() : null;
      case 1:
        if (_quantity <= 0) return 'error_enter_quantity'.tr();
        if (_price < _bounds.min || _price > _bounds.max) {
          return 'error_price_out_of_range'.tr(
            namedArgs: {
              'min': _bounds.min.toStringAsFixed(0),
              'max': _bounds.max.toStringAsFixed(0),
            },
          );
        }
        return null;
      default:
        return null;
    }
  }

  void _next() {
    final error = _blockingError;
    if (error != null) {
      setState(() => _errorMessage = error);
      return;
    }
    setState(() {
      _errorMessage = null;
      _step++;
    });
  }

  void _back() {
    // Unfocus first: with a text field focused (quantity/price, description
    // steps), a tap on the header back button otherwise only dismisses the
    // keyboard, making the button appear unresponsive until tapped again.
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _errorMessage = null;
      _step--;
    });
  }

  Future<void> _pickPhoto() async {
    final source = await showImageSourceSheet(context);
    if (source == null) return;
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      _photoBytes = bytes;
      _photoFileName = picked.name;
    });
  }

  Future<void> _pickHarvestedOn() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _harvestedOn ?? now,
      firstDate: now.subtract(const Duration(days: 90)),
      lastDate: now,
    );
    if (picked != null) setState(() => _harvestedOn = picked);
  }

  Future<void> _publish() async {
    final crop = _crop;
    if (crop == null) return;

    setState(() {
      _isPublishing = true;
      _errorMessage = null;
    });

    try {
      final listingId = const Uuid().v4();
      final userId = widget.profile.id;

      // Only set when the farmer picked a batch-specific photo — left
      // null otherwise so display falls back to the farmer_crop photo.
      String? imageUrl;
      if (_photoBytes != null) {
        imageUrl = await CropPhotoService().uploadListingPhoto(
          userId: userId,
          listingId: listingId,
          bytes: _photoBytes!,
          fileName: _photoFileName ?? 'photo.jpg',
        );
      }

      final description = _descriptionController.text.trim();
      await _listingService.createListing(
        listingId: listingId,
        farmerProfileId: userId,
        cropId: crop.cropId,
        pricePerKg: _price,
        quantityKg: _quantity,
        description: description.isEmpty ? null : description,
        imageUrl: imageUrl,
        harvestedOn: _harvestedOn,
      );

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isPublishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppSecondaryHeader(
        title: 'add_harvest'.tr(),
        onBackPressed: _step == 0
            ? () {
                FocusManager.instance.primaryFocus?.unfocus();
                Navigator.of(context).pop();
              }
            : _back,
        helpText: 'add_harvest_help_body'.tr(),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'step_of'.tr(
                        namedArgs: {
                          'current': '${_step + 1}',
                          'total': '$_stepCount',
                        },
                      ),
                      style: theme.textTheme.labelMedium,
                    ),
                    Text(
                      _stepTitles[_step].tr(),
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (_step + 1) / _stepCount,
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: switch (_step) {
                      0 => _buildCropStep(),
                      1 => _buildQuantityPriceStep(),
                      2 => _buildPhotoStep(),
                      _ => _buildReviewStep(),
                    },
                  ),
                ),
                _buildBottomBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static const _stepTitles = [
    'step_crop',
    'step_quantity_price',
    'step_photo_details',
    'step_review',
  ];

  Widget _buildBottomBar() {
    final theme = Theme.of(context);
    final isReview = _step == _stepCount - 1;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_errorMessage != null) ...[
            Text(
              _errorMessage!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
          ],
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isPublishing ? null : (isReview ? _publish : _next),
              child: _isPublishing
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(isReview ? 'publish_listing'.tr() : 'continue'.tr()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCropStep() {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'what_are_you_harvesting'.tr(),
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'what_are_you_harvesting_subtitle'.tr(),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'search_crops'.tr(),
            prefixIcon: const Icon(Icons.search),
          ),
          onChanged: (value) => setState(() => _search = value),
        ),
        const SizedBox(height: 16),
        StreamBuilder<FarmerProfile?>(
          stream: _farmerProfileStream,
          builder: (context, snapshot) {
            if (!snapshot.hasData && !snapshot.hasError) {
              return const Center(child: CircularProgressIndicator());
            }

            final crops = snapshot.data?.crops ?? [];
            if (crops.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Text(
                  'no_registered_crops'.tr(),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              );
            }

            final filtered = crops
                .where(
                  (c) =>
                      _search.isEmpty ||
                      c.cropName.toLowerCase().contains(_search.toLowerCase()),
                )
                .toList();

            return GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.95,
              children: filtered.map(_buildCropCard).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildCropCard(FarmerCrop crop) {
    final theme = Theme.of(context);
    final isSelected = _crop?.cropId == crop.cropId;

    final borderRadius = BorderRadius.circular(14);

    return InkWell(
      borderRadius: borderRadius,
      onTap: () => _selectCrop(crop),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: borderRadius,
            child: Container(
              color: theme.colorScheme.surfaceContainerLowest,
              child: Column(
                children: [
                  // The image fills the bulk of the card -- only the
                  // name strip below it has a fixed height.
                  Expanded(
                    child: SizedBox(
                      width: double.infinity,
                      child: MediaImage(
                        path: crop.displayImage.path,
                        bucket: crop.displayImage.bucket,
                        public: crop.displayImage.isFallback,
                        placeholder: Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          alignment: Alignment.center,
                          child: Icon(
                            crop.category == 'fruit' ? Icons.apple : Icons.eco,
                            size: 32,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 8,
                    ),
                    child: Text(
                      crop.cropName,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Painted on top of the clipped image/text so the border is
          // never covered at the rounded corners (the image otherwise
          // sits flush against the top edge with nothing to buffer it).
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: borderRadius,
                  border: Border.all(
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant,
                    width: isSelected ? 2 : 1,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuantityPriceStep() {
    final theme = Theme.of(context);
    final bounds = _bounds;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'how_much_listing'.tr(),
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        AppTextField(
          label: 'total_harvest_quantity'.tr(),
          controller: _quantityController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          hintText: '0',
          suffixText: 'kg'.tr(),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        Text(
          'set_your_price'.tr(),
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        AppTextField(
          label: 'price_per_unit_kg'.tr(),
          controller: _priceController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          hintText: '0',
          prefixText: 'Rs ',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.trending_up,
                size: 18,
                color: theme.colorScheme.onSecondaryContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'market_range'.tr(),
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'market_range_hint'.tr(
                        namedArgs: {
                          'min': bounds.min.toStringAsFixed(0),
                          'max': bounds.max.toStringAsFixed(0),
                          'crop': _crop?.cropName ?? '',
                        },
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_crop != null) ...[
          const SizedBox(height: 12),
          MarketPriceComparisonCard(
            cropId: _crop!.cropId,
            farmerPricePerKg: _price,
          ),
        ],
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'estimated_total_value'.tr(),
              style: theme.textTheme.bodyMedium,
            ),
            Text(
              'Rs ${(_quantity * _price).toStringAsFixed(2)}',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPhotoStep() {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'add_photos'.tr(),
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text('add_photos_subtitle'.tr(), style: theme.textTheme.bodyMedium),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: _pickPhoto,
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  height: 260,
                  width: double.infinity,
                  child: _photoBytes != null
                      ? Image.memory(_photoBytes!, fit: BoxFit.cover)
                      : MediaImage(
                          path: _crop?.displayImage.path,
                          bucket: _crop?.displayImage.bucket ?? 'crop-photos',
                          public: _crop?.displayImage.isFallback ?? false,
                          placeholder: Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: Icon(
                              Icons.image_outlined,
                              size: 40,
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ),
                ),
              ),
              Positioned(
                right: 8,
                bottom: 8,
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: theme.colorScheme.primary,
                  child: const Icon(Icons.edit, size: 16, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _photoBytes != null
              ? 'using_new_photo'.tr()
              : (_crop?.displayImage.path != null
                    ? 'using_crop_photo'.tr()
                    : 'no_photo_yet'.tr()),
          style: theme.textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
        if (_photoBytes != null) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => setState(() {
              _photoBytes = null;
              _photoFileName = null;
            }),
            child: Text('revert_to_crop_photo'.tr()),
          ),
        ],
        const SizedBox(height: 20),
        TextField(
          controller: _descriptionController,
          maxLines: 3,
          maxLength: 200,
          decoration: InputDecoration(
            labelText: 'batch_description'.tr(),
            hintText: 'batch_description_hint'.tr(),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _pickHarvestedOn,
          icon: const Icon(Icons.event_outlined),
          label: Text(
            _harvestedOn == null
                ? 'set_harvest_date'.tr()
                : '${'harvested_on'.tr()}: ${_formatDate(_harvestedOn!)}',
          ),
        ),
      ],
    );
  }

  Widget _buildReviewStep() {
    final theme = Theme.of(context);
    final crop = _crop;
    final description = _descriptionController.text.trim();
    final borderRadius = BorderRadius.circular(16);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'review_your_listing'.tr(),
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        Stack(
          children: [
            ClipRRect(
              borderRadius: borderRadius,
              child: Container(
                color: theme.colorScheme.surfaceContainerLowest,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 160,
                      child: _photoBytes != null
                          ? Image.memory(_photoBytes!, fit: BoxFit.cover)
                          : MediaImage(
                              path: crop?.displayImage.path,
                              bucket:
                                  crop?.displayImage.bucket ?? 'crop-photos',
                              public: crop?.displayImage.isFallback ?? false,
                              placeholder: Container(
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                                child: Icon(
                                  Icons.image_outlined,
                                  size: 40,
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            crop?.cropName ?? '',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (description.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(description, style: theme.textTheme.bodySmall),
                          ],
                          const Divider(height: 24),
                          Row(
                            children: [
                              Expanded(
                                child: _ReviewField(
                                  label: 'total_quantity'.tr(),
                                  value: '${_quantity.toStringAsFixed(0)} kg',
                                ),
                              ),
                              Expanded(
                                child: _ReviewField(
                                  label: 'price_per_kg'.tr(),
                                  value: 'Rs ${_price.toStringAsFixed(2)}',
                                  highlight: true,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _ReviewField(
                                  label: 'harvested_on'.tr(),
                                  value: _harvestedOn == null
                                      ? '—'
                                      : _formatDate(_harvestedOn!),
                                ),
                              ),
                              Expanded(
                                child: _ReviewField(
                                  label: 'estimated_total_value'.tr(),
                                  value:
                                      'Rs ${(_quantity * _price).toStringAsFixed(2)}',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Painted on top so the border is never covered at the rounded
            // corners (the image otherwise sits flush against the top edge
            // with nothing to buffer it).
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: borderRadius,
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _formatDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

class _ReviewField extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;

  const _ReviewField({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: theme.textTheme.labelSmall),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: highlight ? theme.colorScheme.primary : null,
          ),
        ),
      ],
    );
  }
}

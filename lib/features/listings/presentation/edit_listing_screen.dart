import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/storage/crop_photo_service.dart';
import '../../../core/widgets/app_secondary_header.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/image_source_sheet.dart';
import '../../../core/widgets/media_image.dart';
import '../../../models/produce_listing.dart';
import '../../pricing/presentation/widgets/market_price_comparison_card.dart';
import '../../profile/farmer/crop_price_bounds.dart';
import '../produce_listing_service.dart';
import 'widgets/listing_status_badge.dart';

/// Farmer-side editor for one published batch, opened by tapping its
/// card on the Harvest tab.
///
/// What's editable, and how, follows from the data model:
///   * Crop — locked. It's the batch's identity (and part of the FK to
///     the farmer's menu); selling a different crop is a new listing.
///   * Price, description, photo, harvest date — a form saved through
///     the local PowerSync mirror, so it works offline. The server clamps
///     price to the crop's bounds; we validate the same range up front.
///   * Stock — separate, live controls (add / remove / mark sold out)
///     that call adjust_own_listing_stock atomically on the server, so an
///     edit can never overwrite a sale that happened meanwhile. Needs a
///     connection; says so.
class EditListingScreen extends StatefulWidget {
  final ProduceListing listing;
  final String farmerProfileId;

  const EditListingScreen({
    super.key,
    required this.listing,
    required this.farmerProfileId,
  });

  @override
  State<EditListingScreen> createState() => _EditListingScreenState();
}

class _EditListingScreenState extends State<EditListingScreen> {
  final _service = ProduceListingService();
  final _priceController = TextEditingController();
  final _descriptionController = TextEditingController();

  /// Live copy of this listing, so stock/status changes (ours via the
  /// RPC, or a buyer's purchase) show up while the screen is open.
  late final Stream<ProduceListing?> _liveListing;

  // Form state (saved together with "Save changes").
  DateTime? _harvestedOn;
  String? _imageUrl; // this batch's own photo override, null = inherit
  Uint8List? _newPhotoBytes;
  String? _newPhotoFileName;

  bool _isSaving = false;
  bool _isAdjustingStock = false;

  /// Result of our last stock RPC, shown until sync brings the local
  /// mirror up to the same value (so the number doesn't jump back).
  double? _stockOverride;

  ProduceListing get _initial => widget.listing;

  @override
  void initState() {
    super.initState();
    _priceController.text = _formatNumber(_initial.pricePerKg);
    _descriptionController.text = _initial.listingDescription ?? '';
    _harvestedOn = _initial.harvestedOn;
    _imageUrl = _initial.listingImageUrl;
    _liveListing = _service
        .watchOwnListings(widget.farmerProfileId)
        .map((all) => all.where((l) => l.id == _initial.id).firstOrNull);
  }

  @override
  void dispose() {
    _priceController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  static String _formatNumber(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  String _formatDate(DateTime d) =>
      DateFormat.yMMMd(context.locale.toString()).format(d);

  double get _price => double.tryParse(_priceController.text) ?? 0;

  ({double min, double max}) get _bounds => priceBoundsFor(_initial.cropName);

  String? get _priceError {
    final b = _bounds;
    if (_price < b.min || _price > b.max) {
      return 'error_price_out_of_range'.tr(
        namedArgs: {
          'min': b.min.toStringAsFixed(0),
          'max': b.max.toStringAsFixed(0),
        },
      );
    }
    return null;
  }

  String? get _descriptionOverride {
    final text = _descriptionController.text.trim();
    return text.isEmpty ? null : text;
  }

  bool get _isDirty =>
      _price != _initial.pricePerKg ||
      _descriptionOverride != _initial.listingDescription ||
      _harvestedOn != _initial.harvestedOn ||
      _imageUrl != _initial.listingImageUrl ||
      _newPhotoBytes != null;

  bool get _canSave => _isDirty && _priceError == null && !_isSaving;

  // --- Photo ---------------------------------------------------------------

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
      _newPhotoBytes = bytes;
      _newPhotoFileName = picked.name;
    });
  }

  /// Drop this batch's own photo so it falls back to the crop's.
  void _useCropPhoto() {
    setState(() {
      _newPhotoBytes = null;
      _newPhotoFileName = null;
      _imageUrl = null;
    });
  }

  // --- Harvest date ----------------------------------------------------------

  Future<void> _pickHarvestedOn() async {
    final now = DateTime.now();
    final earliest = now.subtract(const Duration(days: 90));
    final initial = _harvestedOn ?? now;
    final picked = await showDatePicker(
      context: context,
      // An older date already on the listing stays selectable.
      initialDate: initial.isBefore(earliest) ? earliest : initial,
      firstDate: _harvestedOn != null && _harvestedOn!.isBefore(earliest)
          ? _harvestedOn!
          : earliest,
      lastDate: now,
    );
    if (picked != null) setState(() => _harvestedOn = picked);
  }

  // --- Save ------------------------------------------------------------------

  Future<void> _save() async {
    if (!_canSave) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _isSaving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      var imageUrl = _imageUrl;
      if (_newPhotoBytes != null) {
        imageUrl = await CropPhotoService().uploadListingPhoto(
          userId: widget.farmerProfileId,
          listingId: _initial.id,
          bytes: _newPhotoBytes!,
          fileName: _newPhotoFileName ?? 'photo.jpg',
          // New path per replacement, so cached copies of the old photo
          // are never shown — see uploadListingPhoto.
          version: DateTime.now().millisecondsSinceEpoch.toString(),
        );
      }
      await _service.updateListingDetails(
        listingId: _initial.id,
        pricePerKg: _price,
        description: _descriptionOverride,
        imageUrl: imageUrl,
        harvestedOn: _harvestedOn,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('listing_changes_saved'.tr())),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _isSaving = false);
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<bool> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('discard_changes_title'.tr()),
        content: Text('discard_changes_body'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('keep_editing'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('discard'.tr()),
          ),
        ],
      ),
    );
    return discard == true;
  }

  // --- Stock -----------------------------------------------------------------

  Future<void> _adjustStock(double deltaKg) async {
    setState(() => _isAdjustingStock = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final newQty = await _service.adjustStock(
        listingId: _initial.id,
        deltaKg: deltaKg,
      );
      if (!mounted) return;
      setState(() => _stockOverride = newQty);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'stock_updated'.tr(namedArgs: {'qty': _formatNumber(newQty)}),
          ),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text('stock_update_failed'.tr())),
      );
    } finally {
      if (mounted) setState(() => _isAdjustingStock = false);
    }
  }

  Future<void> _openStockSheet({
    required bool adding,
    required double current,
  }) async {
    final delta = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => _StockAmountSheet(adding: adding, current: current),
    );
    if (delta != null && delta > 0) {
      await _adjustStock(adding ? delta : -delta);
    }
  }

  Future<void> _confirmSoldOut(double current) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('stock_mark_sold_out'.tr()),
        content: Text('stock_mark_sold_out_confirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('cancel'.tr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('stock_mark_sold_out'.tr()),
          ),
        ],
      ),
    );
    // Clamped at 0 server-side, so a sale landing in between can't push
    // stock negative.
    if (ok == true) await _adjustStock(-current);
  }

  // --- Build -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isDirty || _isSaving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmDiscard()) navigator.pop();
      },
      child: Scaffold(
        appBar: AppSecondaryHeader(title: 'edit_listing'.tr()),
        body: StreamBuilder<ProduceListing?>(
          stream: _liveListing,
          initialData: _initial,
          builder: (context, snapshot) {
            final live = snapshot.data ?? _initial;
            // Drop our optimistic value once sync has caught up to it.
            if (_stockOverride != null &&
                live.availableQuantityKg == _stockOverride) {
              _stockOverride = null;
            }
            return SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      _buildPhoto(live),
                      const SizedBox(height: 16),
                      _buildIdentity(live),
                      const SizedBox(height: 16),
                      _buildStockCard(live),
                      const SizedBox(height: 16),
                      _buildDetailsCard(),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        bottomNavigationBar: _buildSaveBar(),
      ),
    );
  }

  Widget _buildPhoto(ProduceListing live) {
    final theme = Theme.of(context);
    final hasOwnPhoto = _newPhotoBytes != null || _imageUrl != null;

    final Widget image;
    if (_newPhotoBytes != null) {
      image = Image.memory(_newPhotoBytes!, fit: BoxFit.cover);
    } else if (_imageUrl != null) {
      image = MediaImage(
        path: _imageUrl,
        bucket: 'crop-photos',
        placeholder: _photoPlaceholder(theme),
      );
    } else {
      // Inherited from the crop / catalogue — same chain as the card.
      final fallback = ProduceListing(
        id: live.id,
        cropId: live.cropId,
        cropName: live.cropName,
        category: live.category,
        pricePerKg: live.pricePerKg,
        availableQuantityKg: live.availableQuantityKg,
        status: live.status,
        farmerCropImageUrl: live.farmerCropImageUrl,
        cropFallbackImageUrl: live.cropFallbackImageUrl,
      ).displayImage;
      image = MediaImage(
        path: fallback.path,
        bucket: fallback.bucket,
        public: fallback.isFallback,
        placeholder: _photoPlaceholder(theme),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 200,
        child: Stack(
          fit: StackFit.expand,
          children: [
            image,
            Positioned(
              top: 10,
              left: 10,
              child: ListingStatusBadge(status: live.status),
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              // Wraps onto two lines on narrow phones / longer si-ta
              // labels instead of overflowing.
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (hasOwnPhoto)
                    _PhotoButton(
                      icon: Icons.restart_alt,
                      label: 'use_crop_photo'.tr(),
                      onPressed: _isSaving ? null : _useCropPhoto,
                    ),
                  _PhotoButton(
                    icon: Icons.photo_camera_outlined,
                    label: 'change_photo'.tr(),
                    onPressed: _isSaving ? null : _pickPhoto,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _photoPlaceholder(ThemeData theme) => Container(
    color: theme.colorScheme.surfaceContainerHighest,
    child: Icon(
      Icons.image_outlined,
      size: 40,
      color: theme.colorScheme.outline,
    ),
  );

  Widget _buildIdentity(ProduceListing live) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          live.cropName,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        if (live.publishedAt != null) ...[
          const SizedBox(height: 2),
          Text(
            'listing_published_on'.tr(
              namedArgs: {'date': _formatDate(live.publishedAt!)},
            ),
            style: theme.textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 8),
        // Why the crop isn't editable, stated up front rather than
        // leaving a field that silently can't be changed.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.lock_outline,
              size: 14,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'edit_listing_crop_locked'.tr(),
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStockCard(ProduceListing live) {
    final theme = Theme.of(context);
    final stock = _stockOverride ?? live.availableQuantityKg;
    final editable = live.isStockEditable;

    return _SectionCard(
      title: 'stock_section_title'.tr(),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _formatNumber(stock),
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: stock > 0
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.error,
              ),
            ),
            const SizedBox(width: 6),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '${'kg'.tr()} · ${'stock_available'.tr()}',
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const Spacer(),
            if (_isAdjustingStock)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (!editable)
          Text('stock_not_editable'.tr(), style: theme.textTheme.bodySmall)
        else ...[
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _isAdjustingStock
                      ? null
                      : () => _openStockSheet(adding: true, current: stock),
                  icon: const Icon(Icons.add),
                  label: Text('stock_add'.tr()),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isAdjustingStock || stock <= 0
                      ? null
                      : () => _openStockSheet(adding: false, current: stock),
                  icon: const Icon(Icons.remove),
                  label: Text('stock_remove'.tr()),
                ),
              ),
            ],
          ),
          if (stock > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _isAdjustingStock
                    ? null
                    : () => _confirmSoldOut(stock),
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  padding: EdgeInsets.zero,
                ),
                icon: const Icon(Icons.remove_shopping_cart_outlined, size: 18),
                label: Text('stock_mark_sold_out'.tr()),
              ),
            ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.wifi, size: 14, color: theme.colorScheme.outline),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'stock_live_note'.tr(),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildDetailsCard() {
    final theme = Theme.of(context);
    final bounds = _bounds;
    final priceError = _priceError;
    final cropDefault = _initial.cropDescription?.trim();

    return _SectionCard(
      title: 'listing_details_title'.tr(),
      children: [
        AppTextField(
          label: 'price_per_unit_kg'.tr(),
          controller: _priceController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          prefixText: 'Rs ',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 6),
        Text(
          priceError ??
              'market_range_hint'.tr(
                namedArgs: {
                  'min': bounds.min.toStringAsFixed(0),
                  'max': bounds.max.toStringAsFixed(0),
                  'crop': _initial.cropName,
                },
              ),
          style: theme.textTheme.bodySmall?.copyWith(
            color: priceError != null ? theme.colorScheme.error : null,
          ),
        ),
        if (priceError == null && _price > 0) ...[
          const SizedBox(height: 8),
          MarketPriceComparisonCard(
            cropId: _initial.cropId,
            farmerPricePerKg: _price,
            compact: true,
          ),
        ],
        const SizedBox(height: 20),
        TextField(
          controller: _descriptionController,
          minLines: 2,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'batch_description'.tr(),
            // Shows what buyers see when this is left empty.
            hintText: cropDefault?.isNotEmpty == true
                ? cropDefault
                : 'batch_description_hint'.tr(),
            helperText: cropDefault?.isNotEmpty == true
                ? 'description_uses_crop_default'.tr()
                : null,
            helperMaxLines: 2,
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 20),
        Text('harvested_on'.tr(), style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickHarvestedOn,
                icon: const Icon(Icons.event_outlined),
                label: Text(
                  _harvestedOn == null
                      ? 'not_set'.tr()
                      : _formatDate(_harvestedOn!),
                ),
                style: OutlinedButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                ),
              ),
            ),
            if (_harvestedOn != null) ...[
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'clear_date'.tr(),
                onPressed: () => setState(() => _harvestedOn = null),
                icon: const Icon(Icons.close),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildSaveBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _canSave ? _save : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text('save_changes'.tr()),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bordered card with a small section title — same chrome as the
/// Harvest tab's cards.
class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SectionCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

/// Small translucent pill button overlaid on the photo.
class _PhotoButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  const _PhotoButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: Colors.black.withValues(alpha: 0.6),
        foregroundColor: Colors.white,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
    );
  }
}

/// Bottom sheet asking how much stock to add or remove, with quick-pick
/// amounts and a live "new total" so the result is clear before
/// confirming. Pops with the (positive) amount, or null.
class _StockAmountSheet extends StatefulWidget {
  final bool adding;
  final double current;

  const _StockAmountSheet({required this.adding, required this.current});

  @override
  State<_StockAmountSheet> createState() => _StockAmountSheetState();
}

class _StockAmountSheetState extends State<_StockAmountSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double get _amount => double.tryParse(_controller.text) ?? 0;

  String? get _error {
    if (!widget.adding && _amount > widget.current) {
      return 'stock_remove_too_much'.tr(
        namedArgs: {'qty': _fmt(widget.current)},
      );
    }
    return null;
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final newTotal = widget.adding
        ? widget.current + _amount
        : (widget.current - _amount).clamp(0, double.infinity).toDouble();
    final valid = _amount > 0 && _error == null;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            (widget.adding ? 'stock_add' : 'stock_remove').tr(),
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          AppTextField(
            label: 'stock_amount_label'.tr(),
            controller: _controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            suffixText: 'kg'.tr(),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final quick in const [5.0, 10.0, 25.0, 50.0])
                if (widget.adding || quick <= widget.current)
                  ActionChip(
                    label: Text('${_fmt(quick)} ${'kg'.tr()}'),
                    onPressed: () =>
                        setState(() => _controller.text = _fmt(quick)),
                  ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _error ?? 'stock_new_total'.tr(namedArgs: {'qty': _fmt(newTotal)}),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: _error != null ? theme.colorScheme.error : null,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: valid ? () => Navigator.of(context).pop(_amount) : null,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            child: Text((widget.adding ? 'stock_add' : 'stock_remove').tr()),
          ),
        ],
      ),
    );
  }
}

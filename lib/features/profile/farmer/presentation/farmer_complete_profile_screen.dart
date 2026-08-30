import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/auth_providers.dart';
import '../../../../core/storage/crop_photo_service.dart';
import '../../../../models/farmer_profile.dart';
import '../farmer_profile_service.dart';
import 'crop_details_sheet.dart';

class FarmerCompleteProfileScreen extends ConsumerStatefulWidget {
  const FarmerCompleteProfileScreen({super.key});

  @override
  ConsumerState<FarmerCompleteProfileScreen> createState() =>
      _FarmerCompleteProfileScreenState();
}

class _FarmerCompleteProfileScreenState
    extends ConsumerState<FarmerCompleteProfileScreen> {
  final _service = FarmerProfileService();
  final _searchController = TextEditingController();

  late final Stream<List<Crop>> _cropsStream;
  final Map<String, CropDetails> _selected = {};

  String _search = '';
  String _categoryFilter = 'all';
  bool _isSubmitting = false;
  bool _completed = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _cropsStream = _service.watchAllCrops();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openCropSheet(Crop crop) async {
    final existing = _selected[crop.id];
    final result = await showCropDetailsSheet(
      context: context,
      cropName: crop.name,
      initialDescription: existing?.description,
      initialPrice: existing?.price,
      onRemove: existing == null
          ? null
          : () => setState(() => _selected.remove(crop.id)),
    );
    if (result != null) {
      setState(() => _selected[crop.id] = result);
    }
  }

  Future<void> _finish() async {
    if (_selected.isEmpty) {
      setState(() => _errorMessage = 'error_select_at_least_one_crop'.tr());
      return;
    }
    await _save(skip: false);
  }

  Future<void> _skip() => _save(skip: true);

  Future<void> _save({required bool skip}) async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final userId = ref.read(authServiceProvider).currentUser!.id;
      final cropPhotoService = CropPhotoService();

      final cropInputs = <FarmerCropInput>[];
      for (final entry in _selected.entries) {
        final draft = entry.value;
        String? imageUrl;
        if (draft.imageBytes != null) {
          imageUrl = await cropPhotoService.upload(
            userId: userId,
            cropId: entry.key,
            bytes: draft.imageBytes!,
            fileName: draft.imageFileName ?? 'photo.jpg',
          );
        }
        cropInputs.add(
          FarmerCropInput(
            cropId: entry.key,
            description: draft.description,
            defaultPricePerKg: draft.price,
            imageUrl: imageUrl,
          ),
        );
      }

      await _service.createProfile(userId, cropInputs);

      if (skip) {
        ref.invalidate(ownProfileProvider);
      } else {
        setState(() => _completed = true);
      }
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Widget _buildCropTile(Crop crop) {
    final theme = Theme.of(context);
    final isSelected = _selected.containsKey(crop.id);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _openCropSheet(crop),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.12)
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? theme.colorScheme.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              crop.category == 'fruit' ? Icons.apple : Icons.eco,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 6),
            Text(
              crop.name,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
            if (isSelected) ...[
              const SizedBox(height: 4),
              Icon(
                Icons.check_circle,
                size: 14,
                color: theme.colorScheme.primary,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text('your_crops_title'.tr())),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: StreamBuilder<List<Crop>>(
              stream: _cropsStream,
              builder: (context, snapshot) {
                if (!snapshot.hasData && !snapshot.hasError) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text(snapshot.error.toString()));
                }

                final crops = snapshot.data ?? [];
                final filtered = crops.where((c) {
                  final matchesSearch =
                      _search.isEmpty ||
                      c.name.toLowerCase().contains(_search.toLowerCase());
                  final matchesCategory =
                      _categoryFilter == 'all' || c.category == _categoryFilter;
                  return matchesSearch && matchesCategory;
                }).toList();

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'your_crops_title'.tr(),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'your_crops_subtitle'.tr(),
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'search_crop_hint'.tr(),
                          prefixIcon: const Icon(Icons.search),
                        ),
                        onChanged: (value) => setState(() => _search = value),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: Text('crop_category_all'.tr()),
                            selected: _categoryFilter == 'all',
                            onSelected: (_) =>
                                setState(() => _categoryFilter = 'all'),
                          ),
                          ChoiceChip(
                            label: Text('crop_category_vegetable'.tr()),
                            selected: _categoryFilter == 'vegetable',
                            onSelected: (_) =>
                                setState(() => _categoryFilter = 'vegetable'),
                          ),
                          ChoiceChip(
                            label: Text('crop_category_fruit'.tr()),
                            selected: _categoryFilter == 'fruit',
                            onSelected: (_) =>
                                setState(() => _categoryFilter = 'fruit'),
                          ),
                        ],
                      ),
                      if (_selected.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Text(
                          'crops_grown'.tr(),
                          style: theme.textTheme.labelLarge,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _selected.keys.map((cropId) {
                            final crop = crops.firstWhere(
                              (c) => c.id == cropId,
                              orElse: () => Crop(
                                id: cropId,
                                name: cropId,
                                category: 'vegetable',
                              ),
                            );
                            return InputChip(
                              label: Text(crop.name),
                              onPressed: () => _openCropSheet(crop),
                              onDeleted: () =>
                                  setState(() => _selected.remove(cropId)),
                            );
                          }).toList(),
                        ),
                      ],
                      const SizedBox(height: 20),
                      GridView.count(
                        crossAxisCount: 3,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 0.95,
                        children: filtered.map(_buildCropTile).toList(),
                      ),
                      if (filtered.isEmpty) ...[
                        const SizedBox(height: 12),
                        Center(child: Text('no_crops_found'.tr())),
                      ],
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _isSubmitting ? null : _skip,
                              child: Text('skip_for_now'.tr()),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _isSubmitting ? null : _finish,
                              child: _isSubmitting
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text('finish'.tr()),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWelcome(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check_circle,
                      color: theme.colorScheme.primary,
                      size: 72,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'welcome_title'.tr(),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'welcome_subtitle'.tr(),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => ref.invalidate(ownProfileProvider),
                      child: Text('go_to_dashboard'.tr()),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _completed ? _buildWelcome(context) : _buildForm(context);
  }
}

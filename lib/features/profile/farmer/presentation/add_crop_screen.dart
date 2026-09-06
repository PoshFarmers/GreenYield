import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/widgets/app_secondary_header.dart';
import '../../../../models/farmer_profile.dart';
import '../farmer_profile_service.dart';
import 'crop_tile.dart';

/// Full-page crop picker for the "Crops Grown" section's Add button —
/// the same search + category-filter + tile-grid interface used by
/// FarmerCompleteProfileScreen's onboarding step, so picking a crop
/// feels consistent whether it happens during onboarding or later from
/// the profile. Unlike onboarding (multi-select), this picks exactly
/// one crop and pops with it; the caller (FarmerProfileViewScreen)
/// drops straight into the details editor for it.
class AddCropScreen extends StatefulWidget {
  final Set<String> registeredCropIds;

  const AddCropScreen({super.key, required this.registeredCropIds});

  @override
  State<AddCropScreen> createState() => _AddCropScreenState();
}

class _AddCropScreenState extends State<AddCropScreen> {
  final _service = FarmerProfileService();
  final _searchController = TextEditingController();

  late final Stream<List<Crop>> _cropsStream;

  String _search = '';
  String _categoryFilter = 'all';

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppSecondaryHeader(title: 'add_crop'.tr()),
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

                final available = (snapshot.data ?? [])
                    .where((c) => !widget.registeredCropIds.contains(c.id))
                    .toList();
                final filtered = available.where((c) {
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
                      const SizedBox(height: 20),
                      if (available.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 32),
                          child: Center(child: Text('all_crops_added'.tr())),
                        )
                      else ...[
                        GridView.count(
                          crossAxisCount: 3,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 0.8,
                          children: filtered
                              .map(
                                (crop) => CropTile(
                                  crop: crop,
                                  isSelected: false,
                                  onTap: () => Navigator.of(context).pop(crop),
                                ),
                              )
                              .toList(),
                        ),
                        if (filtered.isEmpty) ...[
                          const SizedBox(height: 12),
                          Center(child: Text('no_crops_found'.tr())),
                        ],
                      ],
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
}

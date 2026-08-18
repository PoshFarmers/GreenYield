import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/auth_providers.dart';
import '../../../../models/farmer_profile.dart';
import '../farmer_profile_service.dart';

class FarmerCompleteProfileScreen extends ConsumerStatefulWidget {
  const FarmerCompleteProfileScreen({super.key});

  @override
  ConsumerState<FarmerCompleteProfileScreen> createState() =>
      _FarmerCompleteProfileScreenState();
}

class _FarmerCompleteProfileScreenState
    extends ConsumerState<FarmerCompleteProfileScreen> {
  final _service = FarmerProfileService();

  late Future<List<Crop>> _cropsFuture;
  final Set<String> _selectedCropIds = {};

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _cropsFuture = _service.fetchAllCrops();
  }

  Future<void> _submit() async {
    if (_selectedCropIds.isEmpty) {
      setState(() => _errorMessage = 'error_select_at_least_one_crop'.tr());
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final userId = ref.read(authServiceProvider).currentUser!.id;
      await _service.createProfile(userId, _selectedCropIds.toList());
      // AuthGate watches ownProfileProvider and re-checks
      // roleScreensRegistry['farmer'].hasCompletedProfile on rebuild —
      // invalidating here is what actually triggers the move to Home.
      ref.invalidate(ownProfileProvider);
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Widget _buildCropSection(
    BuildContext context, {
    required String titleKey,
    required List<Crop> crops,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titleKey.tr(), style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: crops
              .map(
                (crop) => FilterChip(
                  label: Text(crop.name),
                  selected: _selectedCropIds.contains(crop.id),
                  onSelected: (selected) => setState(() {
                    if (selected) {
                      _selectedCropIds.add(crop.id);
                    } else {
                      _selectedCropIds.remove(crop.id);
                    }
                  }),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('farmer_profile_title'.tr())),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: FutureBuilder<List<Crop>>(
              future: _cropsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(child: Text(snapshot.error.toString()));
                }

                final crops = snapshot.data ?? [];
                final vegetables = crops
                    .where((c) => c.category == 'vegetable')
                    .toList();
                final fruits = crops
                    .where((c) => c.category == 'fruit')
                    .toList();

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'crops_grown'.tr(),
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      _buildCropSection(
                        context,
                        titleKey: 'crop_category_vegetable',
                        crops: vegetables,
                      ),
                      const SizedBox(height: 16),
                      _buildCropSection(
                        context,
                        titleKey: 'crop_category_fruit',
                        crops: fruits,
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _isSubmitting ? null : _submit,
                        child: _isSubmitting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text('save'.tr()),
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
}

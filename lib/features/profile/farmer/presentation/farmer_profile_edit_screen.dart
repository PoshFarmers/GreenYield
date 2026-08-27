import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/auth_providers.dart';
import '../../../../core/storage/avatar_cache_service.dart';
import '../../../../core/storage/avatar_service.dart';
import '../../../../core/widgets/generic_profile_form.dart';
import '../../../../models/farmer_profile.dart';
import '../../../../models/profile.dart';
import '../farmer_profile_service.dart';

class FarmerProfileEditScreen extends ConsumerStatefulWidget {
  final Profile genericProfile;
  final FarmerProfile profile;

  const FarmerProfileEditScreen({
    super.key,
    required this.genericProfile,
    required this.profile,
  });

  @override
  ConsumerState<FarmerProfileEditScreen> createState() =>
      _FarmerProfileEditScreenState();
}

class _FarmerProfileEditScreenState
    extends ConsumerState<FarmerProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _genericController = GenericProfileFormController();
  final _avatarService = AvatarService();
  final _farmerService = FarmerProfileService();

  late final Stream<List<Crop>> _cropsStream;
  late Set<String> _selectedCropIds;

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();

    _selectedCropIds = widget.profile.crops.map((c) => c.id).toSet();
    _cropsStream = _farmerService.watchAllCrops();

    _genericController.loadFrom(widget.genericProfile);
  }

  @override
  void dispose() {
    _genericController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedCropIds.isEmpty) {
      setState(() => _errorMessage = 'error_select_at_least_one_crop'.tr());
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final authService = ref.read(authServiceProvider);
      final userId = authService.currentUser!.id;

      if (_genericController.avatarBytes != null) {
        final avatarPath = await _avatarService.upload(
          userId: userId,
          bytes: _genericController.avatarBytes!,
          fileName: _genericController.avatarFileName ?? 'avatar.jpg',
        );
        await AvatarCacheService().invalidate(avatarPath);
        _genericController.existingAvatarUrl = avatarPath;
      }

      final genericProfile = _genericController.buildProfile(userId);
      await authService.updateOwnProfile(genericProfile);

      await _farmerService.updateCrops(userId, _selectedCropIds.toList());

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _errorMessage = e.toString());
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
      appBar: AppBar(title: Text('edit_profile'.tr())),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    GenericProfileFormSection(controller: _genericController),

                    const SizedBox(height: 24),

                    Text(
                      'crops_grown'.tr(),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),

                    const SizedBox(height: 8),

                    StreamBuilder<List<Crop>>(
                      stream: _cropsStream,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }

                        if (snapshot.hasError) {
                          return Text(snapshot.error.toString());
                        }

                        final crops = snapshot.data ?? [];
                        final vegetables = crops
                            .where((c) => c.category == 'vegetable')
                            .toList();
                        final fruits = crops
                            .where((c) => c.category == 'fruit')
                            .toList();

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
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
                          ],
                        );
                      },
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
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text('save'.tr()),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

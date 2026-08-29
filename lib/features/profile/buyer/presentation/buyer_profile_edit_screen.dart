import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/auth_providers.dart';
import '../../../../core/storage/avatar_cache_service.dart';
import '../../../../core/storage/avatar_service.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/generic_profile_form.dart';
import '../../../../models/buyer_profile.dart';
import '../../../../models/profile.dart';
import '../buyer_profile_service.dart';

class BuyerProfileEditScreen extends ConsumerStatefulWidget {
  final Profile genericProfile;
  final BuyerProfile profile;

  const BuyerProfileEditScreen({
    super.key,
    required this.genericProfile,
    required this.profile,
  });

  @override
  ConsumerState<BuyerProfileEditScreen> createState() =>
      _BuyerProfileEditScreenState();
}

class _BuyerProfileEditScreenState
    extends ConsumerState<BuyerProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _genericController = GenericProfileFormController();
  final _avatarService = AvatarService();
  final _buyerService = BuyerProfileService();

  late String _buyerType;
  late final TextEditingController _buyerLabelController;

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();

    _buyerType = widget.profile.buyerType;
    _buyerLabelController = TextEditingController(
      text: widget.profile.buyerLabel ?? '',
    );

    // Synchronous — data already came from the view screen, no fetch
    // and no loading gap.
    _genericController.loadFrom(widget.genericProfile);
  }

  @override
  void dispose() {
    _genericController.dispose();
    _buyerLabelController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

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

      await _buyerService.updateProfile(
        BuyerProfile(
          profileId: userId,
          buyerType: _buyerType,
          buyerLabel: _buyerLabelController.text.trim().isEmpty
              ? null
              : _buyerLabelController.text.trim(),
        ),
      );

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOrganization = _buyerType == 'organization';

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
                      'buyer_type'.tr(),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: [
                        ButtonSegment(
                          value: 'individual',
                          label: Text('buyer_type_individual'.tr()),
                        ),
                        ButtonSegment(
                          value: 'organization',
                          label: Text('buyer_type_organization'.tr()),
                        ),
                      ],
                      selected: {_buyerType},
                      onSelectionChanged: (s) =>
                          setState(() => _buyerType = s.first),
                    ),
                    if (isOrganization) ...[
                      const SizedBox(height: 16),
                      AppTextField(
                        label: 'buyer_label'.tr(),
                        controller: _buyerLabelController,
                        validator: (v) {
                          if (isOrganization &&
                              (v == null || v.trim().isEmpty)) {
                            return 'error_required'.tr();
                          }
                          return null;
                        },
                      ),
                    ],

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

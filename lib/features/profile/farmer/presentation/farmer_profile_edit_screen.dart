import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/auth_providers.dart';
import '../../../../core/storage/avatar_cache_service.dart';
import '../../../../core/storage/avatar_service.dart';
import '../../../../core/widgets/generic_profile_form.dart';
import '../../../../models/profile.dart';

/// Edits the farmer's personal/profile details only.
///
/// Crops are deliberately not editable here — each crop is managed
/// individually from the Crops Grown section of the profile view, since
/// it carries its own photo/description/price rather than being a plain
/// selection.
class FarmerProfileEditScreen extends ConsumerStatefulWidget {
  final Profile genericProfile;

  const FarmerProfileEditScreen({super.key, required this.genericProfile});

  @override
  ConsumerState<FarmerProfileEditScreen> createState() =>
      _FarmerProfileEditScreenState();
}

class _FarmerProfileEditScreenState
    extends ConsumerState<FarmerProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _genericController = GenericProfileFormController();
  final _avatarService = AvatarService();

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _genericController.loadFrom(widget.genericProfile);
  }

  @override
  void dispose() {
    _genericController.dispose();
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

      await authService.updateOwnProfile(
        _genericController.buildProfile(userId),
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

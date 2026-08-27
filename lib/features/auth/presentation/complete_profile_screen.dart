import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../models/profile.dart';

/// First step of the common (role-agnostic) profile setup flow.
/// Collects the fields every user needs regardless of role, then inserts
/// the `profile` row. AuthGate watches `ownProfileProvider` (a PowerSync
/// stream), so as soon as the insert lands it swaps this screen out on
/// its own — `onComplete` just tells it to re-check now instead of
/// waiting on the next stream tick.
class CompleteProfileScreen extends ConsumerStatefulWidget {
  const CompleteProfileScreen({super.key, required this.onComplete});

  final VoidCallback onComplete;

  @override
  ConsumerState<CompleteProfileScreen> createState() =>
      _CompleteProfileScreenState();
}

class _CompleteProfileScreenState
    extends ConsumerState<CompleteProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _line1Controller = TextEditingController();
  final _line2Controller = TextEditingController();
  final _cityController = TextEditingController();
  final _postalCodeController = TextEditingController();

  static const _languages = [
    ('en', 'English'),
    ('si', 'සිංහල'),
    ('ta', 'தமிழ்'),
  ];

  String _preferredLanguage = 'en';
  File? _avatarFile;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _line1Controller.dispose();
    _line2Controller.dispose();
    _cityController.dispose();
    _postalCodeController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1024,
      imageQuality: 85,
    );
    if (picked != null) {
      setState(() => _avatarFile = File(picked.path));
    }
  }

  void _showAvatarOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text('take_photo'.tr()),
              onTap: () {
                Navigator.of(context).pop();
                _pickAvatar(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text('choose_from_gallery'.tr()),
              onTap: () {
                Navigator.of(context).pop();
                _pickAvatar(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
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

      String? avatarUrl;
      if (_avatarFile != null) {
        avatarUrl = await authService.uploadAvatar(_avatarFile!);
      }

      final profile = Profile(
        id: userId,
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        phone: _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        avatarUrl: avatarUrl,
        preferredLanguage: _preferredLanguage,
        address: Address(
          line1: _line1Controller.text.trim(),
          line2: _line2Controller.text.trim(),
          city: _cityController.text.trim(),
          postalCode: _postalCodeController.text.trim(),
        ),
      );

      await authService.createOwnProfile(profile);
      widget.onComplete();
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text('complete_profile'.tr())),
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
                    Center(
                      child: GestureDetector(
                        onTap: _showAvatarOptions,
                        child: Stack(
                          children: [
                            CircleAvatar(
                              radius: 48,
                              backgroundColor: theme.colorScheme.secondary,
                              backgroundImage: _avatarFile != null
                                  ? FileImage(_avatarFile!)
                                  : null,
                              child: _avatarFile == null
                                  ? Icon(
                                      Icons.person_outline,
                                      size: 40,
                                      color: theme.colorScheme.primary,
                                    )
                                  : null,
                            ),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: CircleAvatar(
                                radius: 16,
                                backgroundColor: theme.colorScheme.primary,
                                child: const Icon(
                                  Icons.edit,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    AppTextField(
                      label: 'first_name'.tr(),
                      controller: _firstNameController,
                      validator: (value) => (value == null || value.trim().isEmpty)
                          ? 'error_required'.tr()
                          : null,
                    ),
                    const SizedBox(height: 16),
                    AppTextField(
                      label: 'last_name'.tr(),
                      controller: _lastNameController,
                      validator: (value) => (value == null || value.trim().isEmpty)
                          ? 'error_required'.tr()
                          : null,
                    ),
                    const SizedBox(height: 16),
                    AppTextField(
                      label: 'phone'.tr(),
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 24),
                    Text('address'.tr(), style: theme.textTheme.labelLarge),
                    const SizedBox(height: 12),
                    AppTextField(
                      label: 'address_line1'.tr(),
                      controller: _line1Controller,
                    ),
                    const SizedBox(height: 16),
                    AppTextField(
                      label: 'address_line2'.tr(),
                      controller: _line2Controller,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: AppTextField(
                            label: 'city'.tr(),
                            controller: _cityController,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AppTextField(
                            label: 'postal_code'.tr(),
                            controller: _postalCodeController,
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text('language'.tr(), style: theme.textTheme.labelLarge),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: _languages.map((entry) {
                        final (code, label) = entry;
                        return ChoiceChip(
                          label: Text(label),
                          selected: _preferredLanguage == code,
                          onSelected: (_) =>
                              setState(() => _preferredLanguage = code),
                        );
                      }).toList(),
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 28),
                    ElevatedButton(
                      onPressed: _isSubmitting ? null : _submit,
                      child: _isSubmitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text('continue'.tr()),
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
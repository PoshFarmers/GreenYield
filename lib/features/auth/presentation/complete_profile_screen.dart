import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../models/profile.dart';

/// Shown exactly once, right after a session exists but no `profile`
class CompleteProfileScreen extends ConsumerStatefulWidget {
  final VoidCallback onComplete;

  const CompleteProfileScreen({super.key, required this.onComplete});

  @override
  ConsumerState<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends ConsumerState<CompleteProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();

  String _preferredLanguage = 'en';
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
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
      await authService.createOwnProfile(
        Profile(
          id: userId,
          firstName: _firstNameController.text.trim(),
          lastName: _lastNameController.text.trim(),
          phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
          preferredLanguage: _preferredLanguage,
        ),
      );
      widget.onComplete();
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('complete_profile_title'.tr())),
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
                    AppTextField(
                      label: 'first_name'.tr(),
                      controller: _firstNameController,
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'error_required'.tr() : null,
                    ),
                    const SizedBox(height: 16),
                    AppTextField(
                      label: 'last_name'.tr(),
                      controller: _lastNameController,
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'error_required'.tr() : null,
                    ),
                    const SizedBox(height: 16),
                    AppTextField(
                      label: 'phone'.tr(),
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 16),
                    Text('language'.tr(), style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'en', label: Text('EN')),
                        ButtonSegment(value: 'si', label: Text('SI')),
                        ButtonSegment(value: 'ta', label: Text('TA')),
                      ],
                      selected: {_preferredLanguage},
                      onSelectionChanged: (s) => setState(() => _preferredLanguage = s.first),
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _errorMessage!,
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    ],
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _isSubmitting ? null : _submit,
                      child: _isSubmitting
                          ? const SizedBox(
                              height: 20, width: 20,
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
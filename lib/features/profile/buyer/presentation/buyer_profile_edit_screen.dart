import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/widgets/app_text_field.dart';
import '../../../../models/buyer_profile.dart';
import '../buyer_profile_service.dart';

class BuyerProfileEditScreen extends StatefulWidget {
  final BuyerProfile profile;

  const BuyerProfileEditScreen({super.key, required this.profile});

  @override
  State<BuyerProfileEditScreen> createState() => _BuyerProfileEditScreenState();
}

class _BuyerProfileEditScreenState extends State<BuyerProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _buyerLabelController;
  final _service = BuyerProfileService();

  late String _buyerType;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _buyerType = widget.profile.buyerType;
    _buyerLabelController = TextEditingController(
      text: widget.profile.buyerLabel ?? '',
    );
  }

  @override
  void dispose() {
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
      await _service.updateProfile(
        BuyerProfile(
          profileId: widget.profile.profileId,
          buyerType: _buyerType,
          buyerLabel: _buyerLabelController.text.trim().isEmpty
              ? null
              : _buyerLabelController.text.trim(),
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _errorMessage = e.toString());
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

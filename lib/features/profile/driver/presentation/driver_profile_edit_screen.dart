import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/auth_providers.dart';
import '../../../../core/storage/avatar_cache_service.dart';
import '../../../../core/storage/avatar_service.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/generic_profile_form.dart';
import '../../../../models/driver_profile.dart';
import '../../../../models/profile.dart';
import '../driver_profile_service.dart';
import 'driver_manage_routes_screen.dart';

const _vehicleTypes = ['three_wheeler', 'van', 'lorry', 'truck', 'tractor'];

class DriverProfileEditScreen extends ConsumerStatefulWidget {
  final Profile genericProfile;
  final DriverProfile profile;

  const DriverProfileEditScreen({
    super.key,
    required this.genericProfile,
    required this.profile,
  });

  @override
  ConsumerState<DriverProfileEditScreen> createState() =>
      _DriverProfileEditScreenState();
}

class _DriverProfileEditScreenState
    extends ConsumerState<DriverProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _genericController = GenericProfileFormController();
  final _avatarService = AvatarService();
  final _driverService = DriverProfileService();

  late String _vehicleType;
  late final TextEditingController _plateNumberController;
  late final TextEditingController _maxLoadController;
  late final TextEditingController _preferredMinLoadController;

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();

    final vehicle = widget.profile.primaryVehicle;

    _vehicleType = vehicle?.vehicleType ?? _vehicleTypes.first;
    _plateNumberController = TextEditingController(
      text: vehicle?.plateNumber ?? '',
    );
    _maxLoadController = TextEditingController(
      text: vehicle?.maxLoadKg.toString() ?? '',
    );
    _preferredMinLoadController = TextEditingController(
      text: vehicle?.preferredMinLoadKg?.toString() ?? '',
    );

    _genericController.loadFrom(widget.genericProfile);
  }

  @override
  void dispose() {
    _genericController.dispose();
    _plateNumberController.dispose();
    _maxLoadController.dispose();
    _preferredMinLoadController.dispose();
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

      final preferredMinLoadText = _preferredMinLoadController.text.trim();
      final updatedVehicle = Vehicle(
        driverProfileId: userId,
        vehicleType: _vehicleType,
        plateNumber: _plateNumberController.text.trim(),
        maxLoadKg: double.parse(_maxLoadController.text.trim()),
        preferredMinLoadKg: preferredMinLoadText.isEmpty
            ? null
            : double.parse(preferredMinLoadText),
      );

      final existingVehicleId = widget.profile.primaryVehicle?.id;
      if (existingVehicleId != null) {
        await _driverService.updateVehicle(existingVehicleId, updatedVehicle);
      } else {
        await _driverService.addVehicle(updatedVehicle);
      }

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

                    const SizedBox(height: 24),

                    Text(
                      'vehicle_type'.tr(),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _vehicleType,
                      items: _vehicleTypes
                          .map(
                            (type) => DropdownMenuItem(
                              value: type,
                              child: Text('vehicle_type_$type'.tr()),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _vehicleType = value);
                        }
                      },
                    ),

                    const SizedBox(height: 16),

                    AppTextField(
                      label: 'plate_number'.tr(),
                      controller: _plateNumberController,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'error_required'.tr();
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 16),

                    AppTextField(
                      label: 'max_load_kg'.tr(),
                      controller: _maxLoadController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (v) {
                        final parsed = double.tryParse((v ?? '').trim());
                        if (parsed == null) return 'error_required'.tr();
                        if (parsed <= 0) return 'error_max_load_positive'.tr();
                        return null;
                      },
                    ),

                    const SizedBox(height: 16),

                    AppTextField(
                      label: 'preferred_min_load_kg'.tr(),
                      controller: _preferredMinLoadController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (v) {
                        final text = (v ?? '').trim();
                        if (text.isEmpty) return null;

                        final parsed = double.tryParse(text);
                        final maxLoad = double.tryParse(
                          _maxLoadController.text.trim(),
                        );
                        if (parsed == null) return 'error_required'.tr();
                        if (maxLoad != null && parsed > maxLoad) {
                          return 'error_min_load_exceeds_max'.tr();
                        }
                        return null;
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

                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => DriverManageRoutesScreen(
                              driverProfileId: widget.profile.profileId,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.alt_route),
                      label: Text('preferred_routes'.tr()),
                    ),

                    const SizedBox(height: 12),

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

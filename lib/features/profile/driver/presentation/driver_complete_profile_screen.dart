import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/auth_providers.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../models/driver_profile.dart';
import '../driver_profile_service.dart';
import 'widgets/route_draft_editor.dart';

const _vehicleTypes = ['three_wheeler', 'van', 'lorry', 'truck', 'tractor'];

class DriverCompleteProfileScreen extends ConsumerStatefulWidget {
  const DriverCompleteProfileScreen({super.key});

  @override
  ConsumerState<DriverCompleteProfileScreen> createState() =>
      _DriverCompleteProfileScreenState();
}

class _DriverCompleteProfileScreenState
    extends ConsumerState<DriverCompleteProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _plateNumberController = TextEditingController();
  final _maxLoadController = TextEditingController();
  final _preferredMinLoadController = TextEditingController();
  final _service = DriverProfileService();

  // Preferred routes are optional at setup time (mandatory fields are
  // vehicle type / plate / max load above) — `_routeDrafts` always has
  // at least one blank draft card so the section isn't empty, but a
  // draft only gets persisted if the user actually fills in both
  // endpoints. See RouteDraft.isFilled.
  final List<RouteDraft> _routeDrafts = [RouteDraft()];

  String _vehicleType = _vehicleTypes.first;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _plateNumberController.dispose();
    _maxLoadController.dispose();
    _preferredMinLoadController.dispose();
    for (final draft in _routeDrafts) {
      draft.dispose();
    }
    super.dispose();
  }

  void _addRouteDraft() => setState(() => _routeDrafts.add(RouteDraft()));

  void _removeRouteDraft(int index) {
    setState(() {
      _routeDrafts[index].dispose();
      _routeDrafts.removeAt(index);
      if (_routeDrafts.isEmpty) _routeDrafts.add(RouteDraft());
    });
  }

  /// [includeRoutes] is false for the "Skip" button — the vehicle form
  /// is still mandatory and gets saved either way, only the routes step
  /// is skippable (and can always be added later from the profile).
  Future<void> _submit({required bool includeRoutes}) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final userId = ref.read(authServiceProvider).currentUser!.id;
      final preferredMinLoadText = _preferredMinLoadController.text.trim();

      final routes = includeRoutes
          ? [
              for (final draft in _routeDrafts)
                if (draft.isFilled) draft.toRoutePreference(userId),
            ]
          : <RoutePreference>[];

      await _service.createProfile(
        userId,
        Vehicle(
          driverProfileId: userId,
          vehicleType: _vehicleType,
          plateNumber: _plateNumberController.text.trim(),
          maxLoadKg: double.parse(_maxLoadController.text.trim()),
          preferredMinLoadKg: preferredMinLoadText.isEmpty
              ? null
              : double.parse(preferredMinLoadText),
        ),
        routes: routes,
      );
      // AuthGate watches ownProfileProvider and re-checks
      // roleScreensRegistry['driver'].hasCompletedProfile on rebuild —
      // invalidating here is what actually triggers the move to Home.
      ref.invalidate(ownProfileProvider);
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('driver_profile_title'.tr())),
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
                        if (parsed == null) {
                          return 'error_required'.tr();
                        }
                        if (parsed <= 0) {
                          return 'error_max_load_positive'.tr();
                        }
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
                        if (parsed == null) {
                          return 'error_required'.tr();
                        }
                        if (maxLoad != null && parsed > maxLoad) {
                          return 'error_min_load_exceeds_max'.tr();
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 28),
                    Text(
                      'where_do_you_usually_drive'.tr(),
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'add_frequent_routes_hint'.tr(),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 16),
                    for (var i = 0; i < _routeDrafts.length; i++) ...[
                      RouteDraftCard(
                        draft: _routeDrafts[i],
                        onRemove: _routeDrafts.length > 1
                            ? () => _removeRouteDraft(i)
                            : null,
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                    ],
                    OutlinedButton.icon(
                      onPressed: _addRouteDraft,
                      icon: const Icon(Icons.add),
                      label: Text('add_another_route'.tr()),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: Theme.of(context).colorScheme.primary,
                          style: BorderStyle.solid,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
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
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _isSubmitting
                                ? null
                                : () => _submit(includeRoutes: false),
                            child: Text('skip'.tr()),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: _isSubmitting
                                ? null
                                : () => _submit(includeRoutes: true),
                            child: _isSubmitting
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text('continue'.tr()),
                          ),
                        ),
                      ],
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

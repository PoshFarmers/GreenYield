import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/auth_providers.dart';
import '../../../../models/driver_profile.dart';
import '../driver_profile_service.dart';
import 'steps/route_selection_step.dart';
import 'steps/vehicle_details_step.dart';

/// Two-step driver onboarding flow — Vehicle Details, then Preferred
/// Route — matching the "Step 1 of 2" / "Step 2 of 2" designs. Replaces
/// the previous single combined form: the vehicle fields are mandatory
/// to advance past step 1, and the route is mandatory to complete
/// registration (it can no longer be skipped during initial onboarding,
/// per the updated requirements — drivers add further routes later from
/// their profile instead).
class DriverRegistrationFlow extends ConsumerStatefulWidget {
  const DriverRegistrationFlow({super.key});

  @override
  ConsumerState<DriverRegistrationFlow> createState() =>
      _DriverRegistrationFlowState();
}

class _DriverRegistrationFlowState
    extends ConsumerState<DriverRegistrationFlow> {
  static const _stepCount = 2;

  final _pageController = PageController();
  final _vehicleFormKey = GlobalKey<FormState>();
  final _service = DriverProfileService();

  final _makeModelController = TextEditingController();
  final _plateNumberController = TextEditingController();
  final _capacityController = TextEditingController();
  final _preferredCapacityController = TextEditingController();
  late final RegistrationRouteDraft _routeDraft = RegistrationRouteDraft();

  String _vehicleType = vehicleCategoryOptions.first.type;
  int _stepIndex = 0;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _pageController.dispose();
    _makeModelController.dispose();
    _plateNumberController.dispose();
    _capacityController.dispose();
    _preferredCapacityController.dispose();
    _routeDraft.dispose();
    super.dispose();
  }

  void _goToStep(int index) {
    setState(() {
      _stepIndex = index;
      _errorMessage = null;
    });
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  void _onContinueFromVehicle() {
    if (!_vehicleFormKey.currentState!.validate()) return;
    _goToStep(1);
  }

  Future<void> _onCompleteRegistration() async {
    if (!_routeDraft.isFilled) {
      setState(() => _errorMessage = 'error_route_endpoints_required'.tr());
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      final userId = ref.read(authServiceProvider).currentUser!.id;
      final preferredText = _preferredCapacityController.text.trim();

      await _service.createProfile(
        userId,
        Vehicle(
          driverProfileId: userId,
          vehicleType: _vehicleType,
          plateNumber: _plateNumberController.text.trim(),
          maxLoadKg: double.parse(_capacityController.text.trim()),
          preferredMinLoadKg: preferredText.isEmpty
              ? null
              : double.parse(preferredText),
        ),
        routes: [_routeDraft.toRoutePreference(userId)],
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

  // "Required fields filled (N/3)" caption under the step-1 CTA —
  // make/model, plate number, and capacity (preferred capacity is
  // optional, matching the "3/3" hint in the design).
  int _filledRequiredFieldCount() {
    var count = 0;
    if (_makeModelController.text.trim().isNotEmpty) count++;
    if (_plateNumberController.text.trim().isNotEmpty) count++;
    if (int.tryParse(_capacityController.text.trim()) != null) count++;
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final maxWidth = width < 480 ? width : 480.0;

    final titleKey = _stepIndex == 0
        ? 'vehicle_details'
        : 'select_preferred_route';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_stepIndex == 0) {
              Navigator.of(context).maybePop();
            } else {
              _goToStep(0);
            }
          },
        ),
        title: Text(titleKey.tr()),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Chip(
              label: Text(
                'step_x_of_n'.tr(
                  namedArgs: {
                    'step': '${_stepIndex + 1}',
                    'total': '$_stepCount',
                  },
                ),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              backgroundColor: theme.colorScheme.primary.withValues(
                alpha: 0.12,
              ),
              side: BorderSide.none,
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: (_stepIndex + 1) / _stepCount,
            minHeight: 4,
            backgroundColor: theme.colorScheme.outlineVariant,
            valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: PageView(
                    controller: _pageController,
                    // Driven entirely by the buttons below, not swipes —
                    // step 1's fields must validate before step 2 opens.
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      VehicleDetailsStep(
                        formKey: _vehicleFormKey,
                        selectedType: _vehicleType,
                        onTypeChanged: (type) =>
                            setState(() => _vehicleType = type),
                        makeModelController: _makeModelController,
                        plateNumberController: _plateNumberController,
                        capacityController: _capacityController,
                        preferredCapacityController:
                            _preferredCapacityController,
                      ),
                      RouteSelectionStep(
                        draft: _routeDraft,
                        onChanged: () => setState(() {}),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            AnimatedBuilder(
              // Repaints the "(N/3) filled" caption live as the driver
              // types, without threading onChanged through every field.
              animation: Listenable.merge([
                _makeModelController,
                _plateNumberController,
                _capacityController,
              ]),
              builder: (context, _) => _BottomBar(
                maxWidth: maxWidth,
                stepIndex: _stepIndex,
                isSubmitting: _isSubmitting,
                errorMessage: _errorMessage,
                canCompleteRoute: _routeDraft.isFilled,
                filledRequiredFields: _filledRequiredFieldCount(),
                onBack: () => _goToStep(0),
                onContinue: _onContinueFromVehicle,
                onComplete: _onCompleteRegistration,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final double maxWidth;
  final int stepIndex;
  final bool isSubmitting;
  final String? errorMessage;
  final bool canCompleteRoute;
  final int filledRequiredFields;
  final VoidCallback onBack;
  final VoidCallback onContinue;
  final VoidCallback onComplete;

  const _BottomBar({
    required this.maxWidth,
    required this.stepIndex,
    required this.isSubmitting,
    required this.errorMessage,
    required this.canCompleteRoute,
    required this.filledRequiredFields,
    required this.onBack,
    required this.onContinue,
    required this.onComplete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (errorMessage != null) ...[
                Text(
                  errorMessage!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                const SizedBox(height: 8),
              ],
              if (stepIndex == 0)
                ElevatedButton.icon(
                  onPressed: onContinue,
                  icon: const Icon(Icons.arrow_forward),
                  label: Text('continue_to_route_selection'.tr()),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: isSubmitting ? null : onBack,
                        icon: const Icon(Icons.tune),
                        label: Text('change_locations'.tr()),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: (isSubmitting || !canCompleteRoute)
                            ? null
                            : onComplete,
                        icon: isSubmitting
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.check_circle_outline),
                        label: Text('complete_registration'.tr()),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 6),
              Text(
                stepIndex == 0
                    ? 'required_fields_filled'.tr(
                        namedArgs: {'count': '$filledRequiredFields'},
                      )
                    : 'route_selection_mandatory_hint'.tr(),
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

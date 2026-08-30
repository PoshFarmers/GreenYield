import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../models/driver_profile.dart';
import '../driver_profile_service.dart';
import 'widgets/route_draft_editor.dart';

/// Add-or-edit screen for a single driver's preferred route, reached
/// from the profile's "Manage Routes" list (the `+` button, or an
/// existing route's "Edit Route" link). Mirrors the account-setup
/// "Preferred Routes" step visually, but always operates on exactly one
/// route and always writes immediately (no vehicle form alongside it).
class DriverRouteSetupScreen extends StatefulWidget {
  final String driverProfileId;
  final RoutePreference? existingRoute;

  const DriverRouteSetupScreen({
    super.key,
    required this.driverProfileId,
    this.existingRoute,
  });

  @override
  State<DriverRouteSetupScreen> createState() =>
      _DriverRouteSetupScreenState();
}

class _DriverRouteSetupScreenState extends State<DriverRouteSetupScreen> {
  final _service = DriverProfileService();
  late final RouteDraft _draft;
  bool _isSubmitting = false;
  String? _errorMessage;

  bool get _isEditing => widget.existingRoute != null;

  @override
  void initState() {
    super.initState();
    _draft = widget.existingRoute != null
        ? RouteDraft.fromRoutePreference(widget.existingRoute!)
        : RouteDraft();
  }

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_draft.isFilled) {
      setState(() => _errorMessage = 'error_route_endpoints_required'.tr());
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      final route = _draft.toRoutePreference(widget.driverProfileId);
      if (_isEditing) {
        await _service.updateRoute(_draft.existingId!, route);
      } else {
        await _service.addRoute(route);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('preferred_routes'.tr()),
        actions: [
          IconButton(
            tooltip: 'help'.tr(),
            icon: const Icon(Icons.help_outline),
            onPressed: () {},
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'where_do_you_usually_drive'.tr(),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'add_frequent_routes_hint'.tr(),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 20),
                  RouteDraftCard(draft: _draft, onChanged: (_) {}),
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
                              : () => Navigator.of(context).maybePop(),
                          child: Text('skip'.tr()),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: _isSubmitting ? null : _save,
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
    );
  }
}

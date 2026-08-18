import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_providers.dart';

/// Shown once the generic profile exists but the user holds no role yet
class RoleSelectionScreen extends ConsumerStatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  ConsumerState<RoleSelectionScreen> createState() =>
      _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends ConsumerState<RoleSelectionScreen> {
  bool _isSubmitting = false;
  String? _errorMessage;

  Future<void> _selectRole(String role) async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      final authService = ref.read(authServiceProvider);
      await authService.addRole(role);
      await authService.setActiveRole(role);
      ref.invalidate(ownRolesProvider);
      ref.invalidate(ownProfileProvider);
      // AuthGate reacts to both providers changing and routes onward
      // on its own — no navigation call needed here.
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('select_role_title'.tr())),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'select_role_subtitle'.tr(),
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  _RoleCard(
                    icon: Icons.agriculture,
                    label: 'role_farmer'.tr(),
                    enabled: !_isSubmitting,
                    onTap: () => _selectRole('farmer'),
                  ),
                  const SizedBox(height: 16),
                  _RoleCard(
                    icon: Icons.storefront,
                    label: 'role_buyer'.tr(),
                    enabled: !_isSubmitting,
                    onTap: () => _selectRole('buyer'),
                  ),
                  const SizedBox(height: 16),
                  _RoleCard(
                    icon: Icons.local_shipping,
                    label: 'role_driver'.tr(),
                    enabled: !_isSubmitting,
                    onTap: () => _selectRole('driver'),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _RoleCard({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Card(
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Row(
              children: [
                Icon(icon, size: 32),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

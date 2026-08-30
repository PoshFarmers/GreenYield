import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_providers.dart';

class _RoleOption {
  const _RoleOption(this.value, this.icon, this.titleKey, this.subtitleKey);

  final String value;
  final IconData icon;
  final String titleKey;
  final String subtitleKey;
}

const _roleOptions = [
  _RoleOption('farmer', Icons.eco_outlined, 'role_farmer', 'role_farmer_desc'),
  _RoleOption(
    'buyer',
    Icons.shopping_basket_outlined,
    'role_buyer',
    'role_buyer_desc',
  ),
  _RoleOption(
    'driver',
    Icons.local_shipping_outlined,
    'role_driver',
    'role_driver_desc',
  ),
];

/// Step 2 of profile setup. Writes the chosen role via `addRole` +
/// `setActiveRole`; AuthGate watches `ownRolesProvider` (also a
/// PowerSync stream) and swaps this screen out once the row lands, so
/// there's nothing to navigate to manually here either.
class RoleSelectionScreen extends ConsumerStatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  ConsumerState<RoleSelectionScreen> createState() =>
      _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends ConsumerState<RoleSelectionScreen> {
  String? _selected;
  bool _isSubmitting = false;

  Future<void> _continue() async {
    final role = _selected;
    if (role == null) return;
    setState(() => _isSubmitting = true);
    final authService = ref.read(authServiceProvider);
    await authService.addRole(role);
    await authService.setActiveRole(role);
    // No setState/navigation here on purpose — AuthGate reacts to the
    // ownRolesProvider stream and rebuilds past this screen itself. If
    // the write fails, an uncaught exception here is loud on purpose
    // during development; wrap in try/catch + error text once this
    // flow is stable.
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.agriculture, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              'app_name'.tr(),
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'role_selection_title'.tr(),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'role_selection_subtitle'.tr(),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 28),
                  ..._roleOptions.map(
                    (option) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _RoleCard(
                        option: option,
                        selected: _selected == option.value,
                        onTap: () => setState(() => _selected = option.value),
                      ),
                    ),
                  ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: (_selected == null || _isSubmitting)
                        ? null
                        : _continue,
                    child: _isSubmitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('continue'.tr()),
                              const SizedBox(width: 8),
                              const Icon(Icons.arrow_forward, size: 18),
                            ],
                          ),
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

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _RoleOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: colors.surface,
          border: Border.all(
            color: selected ? colors.primary : colors.outline,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: colors.secondary,
              child: Icon(option.icon, color: colors.primary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.titleKey.tr(),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    option.subtitleKey.tr(),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

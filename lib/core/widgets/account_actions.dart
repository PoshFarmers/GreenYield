import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/sign_out.dart';

/// Log out + Delete account, shown at the bottom of every role's profile
/// view so the two actions look and behave the same for farmers, buyers
/// and drivers.
///
/// Both are clearly-bordered, full-width red buttons so they read as
/// real, consequential actions. Delete account additionally gets a red
/// tint — it's the irreversible one — so the two are never confused.
/// Both confirm before acting.
class AccountActions extends ConsumerWidget {
  const AccountActions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    const padding = EdgeInsets.symmetric(vertical: 14);
    final border = BorderSide(color: scheme.error, width: 1.5);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: () => confirmAndSignOut(context, ref),
          icon: const Icon(Icons.logout),
          label: Text('logout'.tr()),
          style: OutlinedButton.styleFrom(
            foregroundColor: scheme.error,
            side: border,
            padding: padding,
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _confirmDeleteAccount(context),
          icon: const Icon(Icons.delete_outline),
          label: Text('delete_account'.tr()),
          style: OutlinedButton.styleFrom(
            foregroundColor: scheme.error,
            backgroundColor: scheme.error.withValues(alpha: 0.08),
            side: border,
            padding: padding,
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          icon: Icon(Icons.warning_amber_rounded, color: scheme.error),
          title: Text('delete_account'.tr()),
          content: Text('delete_account_confirm_body'.tr()),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text('cancel'.tr()),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text('delete'.tr()),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) return;
    // TODO: wire up once account deletion exists server-side
    // (no `delete_own_account` RPC / endpoint yet).
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('delete_account_not_available'.tr())),
    );
  }
}

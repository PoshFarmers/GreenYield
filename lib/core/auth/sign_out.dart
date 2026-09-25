import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/navigation/presentation/app_nav_shell.dart';
import 'auth_providers.dart';

/// Pops every pushed route (so AuthGate is visible), resets the bottom-nav
/// tab, then signs out. Everything is read from `ref` BEFORE popping,
/// because the calling widget is disposed afterwards.
Future<void> signOutAndReset(BuildContext context, WidgetRef ref) async {
  final navigator = Navigator.of(context);
  final auth = ref.read(authServiceProvider);
  final shell = ref.read(navShellIndexProvider.notifier);

  navigator.popUntil((route) => route.isFirst);
  shell.select(0);
  await auth.signOut();
}

/// The one log-out entry point for UI: asks first, then signs out. Every
/// role's logout button goes through this so the confirmation is the
/// same everywhere.
Future<void> confirmAndSignOut(BuildContext context, WidgetRef ref) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final scheme = Theme.of(dialogContext).colorScheme;
      return AlertDialog(
        icon: Icon(Icons.logout, color: scheme.error),
        title: Text('logout'.tr()),
        content: Text('logout_confirm_body'.tr()),
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
            child: Text('logout'.tr()),
          ),
        ],
      );
    },
  );
  if (confirmed == true && context.mounted) {
    await signOutAndReset(context, ref);
  }
}

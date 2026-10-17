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

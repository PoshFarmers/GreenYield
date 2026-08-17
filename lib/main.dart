import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/auth/auth_gate.dart';
import 'core/localization/multi_file_asset_loader.dart';
import 'core/supabase/client.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  await initSupabase();

  // Created manually (rather than letting ProviderScope create its own)
  final container = ProviderContainer();
  await container.read(themeModeProvider.notifier).loadSavedTheme();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: EasyLocalization(
        supportedLocales: const [Locale('en'), Locale('si'), Locale('ta')],
        path: 'assets/translations',
        assetLoader: const MultiFileAssetLoader(),
        fallbackLocale: const Locale('en'),
        child: const GreenYieldApp(),
      ),
    ),
  );
}

class GreenYieldApp extends ConsumerWidget {
  const GreenYieldApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: 'GreenYield',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      home: const AuthGate(),
    );
  }
}

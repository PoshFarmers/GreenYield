import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/localization/locale_rebuild_scope.dart';
import 'core/localization/multi_file_asset_loader.dart';
import 'core/supabase/client.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'core/local_db/powersync.dart';
import 'features/onboarding/onboarding_prefs.dart';
import 'features/onboarding/presentation/app_entry.dart';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  // Keep the native launch screen up through init; SplashScreen removes
  // it on its first frame so the hand-off is seamless.
  FlutterNativeSplash.preserve(widgetsBinding: binding);

  await EasyLocalization.ensureInitialized();
  await initSupabase();
  await initPowerSync();

  // Created manually (rather than letting ProviderScope create its own)
  final container = ProviderContainer();
  await container.read(themeModeProvider.notifier).loadSavedTheme();

  // Returning users who are already signed in (e.g. upgraded from a
  // build without onboarding) skip the intro even if the flag is unset.
  final showOnboarding =
      supabase.auth.currentSession == null && !await OnboardingPrefs.hasSeen();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: EasyLocalization(
        supportedLocales: const [Locale('en'), Locale('si'), Locale('ta')],
        path: 'assets/translations',
        assetLoader: const MultiFileAssetLoader(),
        fallbackLocale: const Locale('en'),
        child: GreenYieldApp(showOnboarding: showOnboarding),
      ),
    ),
  );
}

class GreenYieldApp extends ConsumerWidget {
  final bool showOnboarding;

  const GreenYieldApp({super.key, required this.showOnboarding});

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
      builder: (context, child) =>
          LocaleRebuildScope(locale: context.locale, child: child!),
      home: AppEntry(showOnboarding: showOnboarding),
    );
  }
}

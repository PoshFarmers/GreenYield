import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../models/profile.dart';

/// Placeholder landing page for every signed-in user
class HomeScreen extends ConsumerWidget {
  final Profile profile;

  const HomeScreen({super.key, required this.profile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('home_title'.tr()),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'logout'.tr(),
            onPressed: () => ref.read(authServiceProvider).signOut(),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('welcome'.tr(), style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  '${'signed_in_as'.tr()}: ${profile.firstName} ${profile.lastName}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 32),
                Text('toggle_theme'.tr(), style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode)),
                    ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode)),
                    ButtonSegment(value: ThemeMode.system, label: Text('System'), icon: Icon(Icons.settings_suggest)),
                  ],
                  selected: {themeMode},
                  onSelectionChanged: (s) => ref.read(themeModeProvider.notifier).setThemeMode(s.first),
                ),
                const SizedBox(height: 24),
                Text('language'.tr(), style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                DropdownButton<Locale>(
                  value: context.locale,
                  items: context.supportedLocales
                      .map((locale) => DropdownMenuItem(
                            value: locale,
                            child: Text(locale.languageCode.toUpperCase()),
                          ))
                      .toList(),
                  onChanged: (locale) {
                    if (locale != null) context.setLocale(locale);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
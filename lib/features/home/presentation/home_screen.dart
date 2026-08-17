import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/storage/avatar_service.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../models/profile.dart';

/// Landing page for every signed-in user. Shows the profile's name and
/// avatar, plus the existing theme/language controls.
class HomeScreen extends ConsumerStatefulWidget {
  final Profile profile;

  const HomeScreen({super.key, required this.profile});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _avatarService = AvatarService();

  String? _avatarSignedUrl;

  @override
  void initState() {
    super.initState();
    _loadAvatar();
  }

  Future<void> _loadAvatar() async {
    final path = widget.profile.avatarUrl;
    if (path == null) return;
    try {
      final url = await _avatarService.signedUrl(path);
      if (mounted) setState(() => _avatarSignedUrl = url);
    } catch (_) {
      // Avatar failing to load isn't fatal — just fall back to the
      // placeholder icon below.
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final profile = widget.profile;

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
                CircleAvatar(
                  radius: 48,
                  backgroundImage:
                      _avatarSignedUrl != null ? NetworkImage(_avatarSignedUrl!) : null,
                  child: _avatarSignedUrl == null ? const Icon(Icons.person, size: 48) : null,
                ),
                const SizedBox(height: 16),
                Text(
                  '${profile.firstName} ${profile.lastName}',
                  style: Theme.of(context).textTheme.headlineSmall,
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
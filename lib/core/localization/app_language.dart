import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';

/// One of the app's supported languages. Names are always shown in their
/// own script ("සිංහල", not "Sinhala"), so someone who can't read the
/// current UI language can still find theirs.
class AppLanguage {
  final String code;
  final String nativeName;
  final String englishName;

  /// A single representative letter, used as the option's badge.
  final String glyph;

  const AppLanguage(this.code, this.nativeName, this.englishName, this.glyph);

  static const all = [
    AppLanguage('si', 'සිංහල', 'Sinhala', 'අ'),
    AppLanguage('ta', 'தமிழ்', 'Tamil', 'அ'),
    AppLanguage('en', 'English', 'English', 'A'),
  ];

  static AppLanguage of(String code) =>
      all.firstWhere((l) => l.code == code, orElse: () => all.last);

  static AppLanguage current(BuildContext context) =>
      of(context.locale.languageCode);
}

/// The single way to change the app's language: switches the UI right
/// away (easy_localization also persists it on-device) and, if signed
/// in, mirrors it to `profile.preferred_language` so server-side things
/// (notifications, etc.) speak the same language.
///
/// The device is the source of truth for the UI — the language is picked
/// on first launch before anyone signs in — and the profile follows it.
Future<void> applyLanguage(
  BuildContext context,
  WidgetRef ref,
  String code,
) async {
  if (context.locale.languageCode != code) {
    await context.setLocale(Locale(code));
  }
  await ref.read(authServiceProvider).updatePreferredLanguage(code);
}

/// Bottom-sheet language picker, for anywhere outside onboarding (login,
/// settings rows). Applies the choice immediately and closes.
class LanguagePickerSheet {
  LanguagePickerSheet._();

  static Future<void> show(BuildContext context, WidgetRef ref) {
    return showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final current = AppLanguage.current(sheetContext);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'language'.tr(),
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                for (final language in AppLanguage.all) ...[
                  LanguageOptionCard(
                    language: language,
                    selected: language.code == current.code,
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      unawaited(applyLanguage(context, ref, language.code));
                    },
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Large, tappable language option: script badge, native name, English
/// name underneath, and a check when selected.
class LanguageOptionCard extends StatelessWidget {
  final AppLanguage language;
  final bool selected;
  final VoidCallback onTap;

  const LanguageOptionCard({
    super.key,
    required this.language,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? scheme.secondary : scheme.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? scheme.primary : scheme.outline,
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected ? scheme.primary : scheme.secondary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    language.glyph,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: selected ? scheme.onPrimary : scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        language.nativeName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (language.englishName != language.nativeName)
                        Text(
                          language.englishName,
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: selected
                      ? Icon(
                          Icons.check_circle,
                          key: const ValueKey('on'),
                          color: scheme.primary,
                        )
                      : Icon(
                          Icons.circle_outlined,
                          key: const ValueKey('off'),
                          color: scheme.outline,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

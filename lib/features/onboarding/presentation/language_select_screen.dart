import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/localization/app_language.dart';
import '../../../core/widgets/app_logo.dart';

/// Very first screen on a fresh install, right after the splash — before
/// the intro carousel and login, so everything after it is already in
/// the user's language.
///
/// The prompt is shown in all three languages at once (someone who only
/// reads Tamil can't be expected to find "Choose your language"), the
/// phone's own language is preselected, and tapping an option switches
/// the whole screen live so the choice is confirmed before Continue.
class LanguageSelectScreen extends ConsumerWidget {
  final VoidCallback onContinue;

  const LanguageSelectScreen({super.key, required this.onContinue});

  /// Deliberately not translated — every line is always visible.
  static const _prompts = [
    ('si', 'ඔබේ භාෂාව තෝරන්න'),
    ('ta', 'உங்கள் மொழியைத் தேர்ந்தெடுக்கவும்'),
    ('en', 'Choose your language'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          // Scrolls on short screens / large text, but otherwise pins
          // Continue to the bottom via the Spacer.
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(child: _buildBody(context, ref)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final current = AppLanguage.current(context);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: AppLogo(size: 72)),
              const SizedBox(height: 28),
              // The prompt in the selected language is emphasised;
              // the other two stay visible but quieter.
              for (final (code, prompt) in _prompts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    textAlign: TextAlign.center,
                    style: code == current.code
                        ? GoogleFonts.outfit(
                            textStyle: theme.textTheme.titleLarge,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onSurface,
                          )
                        : GoogleFonts.outfit(
                            textStyle: theme.textTheme.bodyLarge,
                            color: theme.textTheme.bodySmall?.color,
                          ),
                    child: Text(prompt, textAlign: TextAlign.center),
                  ),
                ),
              const SizedBox(height: 28),
              for (final language in AppLanguage.all) ...[
                LanguageOptionCard(
                  language: language,
                  selected: language.code == current.code,
                  onTap: () => applyLanguage(context, ref, language.code),
                ),
                const SizedBox(height: 12),
              ],
              const Spacer(),
              Text(
                'language_change_later'.tr(),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: onContinue,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  shape: const StadiumBorder(),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'language_continue'.tr(),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward, size: 20),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

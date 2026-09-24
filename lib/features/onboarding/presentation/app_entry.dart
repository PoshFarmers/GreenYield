import 'package:flutter/material.dart';

import '../../../core/auth/auth_gate.dart';
import '../onboarding_prefs.dart';
import 'language_select_screen.dart';
import 'onboarding_screen.dart';
import 'splash_screen.dart';

enum _EntryPhase { splash, language, onboarding, app }

/// The app's root: animated splash → (first launch only) language
/// choice → intro carousel → [AuthGate]. State-driven like AuthGate itself — no routes are pushed,
/// so there's nothing for the back button to return to.
class AppEntry extends StatefulWidget {
  /// Decided in main() before the first frame (device hasn't seen the
  /// intro AND nobody is signed in), so there's no flash of the wrong
  /// screen while SharedPreferences loads.
  final bool showOnboarding;

  const AppEntry({super.key, required this.showOnboarding});

  @override
  State<AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends State<AppEntry> {
  _EntryPhase _phase = _EntryPhase.splash;

  void _onSplashFinished() {
    setState(
      () => _phase = widget.showOnboarding
          ? _EntryPhase.language
          : _EntryPhase.app,
    );
  }

  void _onOnboardingDone() {
    // Fire-and-forget: if the write fails the worst case is seeing the
    // intro once more, not worth blocking the transition on.
    OnboardingPrefs.markSeen();
    setState(() => _phase = _EntryPhase.app);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: switch (_phase) {
        _EntryPhase.splash => SplashScreen(
          key: const ValueKey('splash'),
          onFinished: _onSplashFinished,
        ),
        _EntryPhase.language => LanguageSelectScreen(
          key: const ValueKey('language'),
          onContinue: () => setState(() => _phase = _EntryPhase.onboarding),
        ),
        _EntryPhase.onboarding => OnboardingScreen(
          key: const ValueKey('onboarding'),
          onDone: _onOnboardingDone,
        ),
        _EntryPhase.app => const AuthGate(key: ValueKey('app')),
      },
    );
  }
}

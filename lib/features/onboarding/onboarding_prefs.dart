import 'package:shared_preferences/shared_preferences.dart';

/// Whether this device has already been through the intro carousel.
/// Per-device (SharedPreferences), not per-account: it's an introduction
/// to the app itself, shown before anyone signs in.
class OnboardingPrefs {
  OnboardingPrefs._();

  static const _seenKey = 'onboarding_seen';

  static Future<bool> hasSeen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_seenKey) ?? false;
  }

  static Future<void> markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_seenKey, true);
  }
}

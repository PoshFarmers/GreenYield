import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which implementation a "smart" feature uses. `mock` never touches the
/// network; `real` calls the backend and falls back to the mock on any
/// failure.
enum AiMode { mock, real }

/// Non-secret feature flags read from `.env` (loaded in `initSupabase`).
/// Never put API keys here — anything in `.env` ships inside the app.
/// Secrets live in Supabase (`supabase secrets set ...`) and are only
/// read by Edge Functions.
class AppConfig {
  const AppConfig({
    required this.listingAssistantMode,
    required this.driverTipsMode,
  });

  /// `AI_ASSISTANT_MODE=mock|gemini` — Snap-to-List. Defaults to `gemini`
  /// (real, with automatic mock fallback); any unrecognised value is
  /// treated as `mock` so a typo can never make network calls.
  final AiMode listingAssistantMode;

  /// `DRIVER_TIPS_MODE=mock|real` — Weather-Smart Driver Tips. Defaults to
  /// `mock`; the real (Open-Meteo + Gemini) version isn't built yet, so
  /// `real` currently also uses the mock.
  final AiMode driverTipsMode;

  factory AppConfig.fromEnv() {
    String? read(String key) => dotenv.isInitialized ? dotenv.env[key] : null;
    return AppConfig(
      listingAssistantMode: switch (read('AI_ASSISTANT_MODE')?.trim()) {
        null || '' || 'gemini' => AiMode.real,
        _ => AiMode.mock,
      },
      driverTipsMode: read('DRIVER_TIPS_MODE')?.trim() == 'real'
          ? AiMode.real
          : AiMode.mock,
    );
  }
}

final appConfigProvider = Provider<AppConfig>((_) => AppConfig.fromEnv());

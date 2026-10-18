/// Models for Weather-Smart Driver Tips. Kept free of Flutter so the
/// rules (driver_tip_rules.dart) are plain, unit-testable Dart.
library;

enum TipSeverity { info, caution, warning }

/// The weather "story" a day follows. In mock mode this drives the sample
/// forecast; a presenter can pick one from the demo sheet.
enum WeatherScenario { rainyAfternoon, hotDry, clearMild, windy }

class HourlyWeather {
  /// Local hour of day (Asia/Colombo), 0-23.
  final int hour;
  final int rainProbability; // %
  final double temperatureC;
  final double windKmh;

  const HourlyWeather({
    required this.hour,
    required this.rainProbability,
    required this.temperatureC,
    required this.windKmh,
  });
}

class WeatherSummary {
  final List<HourlyWeather> hours;

  /// True for the mock/sample forecast — the UI labels it as such.
  final bool isSample;

  const WeatherSummary({required this.hours, required this.isSample});

  int get maxRainProbability =>
      hours.fold(0, (m, h) => h.rainProbability > m ? h.rainProbability : m);
  double get maxTemperatureC =>
      hours.fold(-100, (m, h) => h.temperatureC > m ? h.temperatureC : m);
  double get maxWindKmh =>
      hours.fold(0, (m, h) => h.windKmh > m ? h.windKmh : m);
}

/// What's on the truck today, derived from the stops' crop names.
class CargoProfile {
  final List<String> crops;
  final List<String> leafy;
  final List<String> delicate;
  final int pendingPickups;
  final int pendingStops;

  /// True when this is the demo's sample cargo, not real stops.
  final bool isSample;

  const CargoProfile({
    required this.crops,
    required this.leafy,
    required this.delicate,
    required this.pendingPickups,
    required this.pendingStops,
    this.isSample = false,
  });

  bool get isEmpty => pendingStops == 0;
}

/// A tip before it's turned into user-facing text: translation keys plus
/// already-formatted arguments. The ids are stable per rule, so "Got it"
/// dismissals survive a rebuild.
class TipDraft {
  final String id;
  final TipSeverity severity;
  final String titleKey;
  final String bodyKey;
  final Map<String, String> args;
  final List<String> relatedCrops;
  final String? timeWindow;

  const TipDraft({
    required this.id,
    required this.severity,
    required this.titleKey,
    required this.bodyKey,
    this.args = const {},
    this.relatedCrops = const [],
    this.timeWindow,
  });
}

/// A user-facing tip (the brief's DriverTip model). Mock tips are rendered
/// from [TipDraft]s; a real AI implementation returns these directly.
class DriverTip {
  final String id;
  final TipSeverity severity;
  final String title;
  final String body;
  final String? relatedStopId;
  final String? timeWindow;
  final List<String> relatedCrops;

  const DriverTip({
    required this.id,
    required this.severity,
    required this.title,
    required this.body,
    this.relatedStopId,
    this.timeWindow,
    this.relatedCrops = const [],
  });
}

class DriverTipsResult {
  final WeatherSummary weather;
  final WeatherScenario scenario;
  final List<DriverTip> tips;
  final CargoProfile cargo;

  const DriverTipsResult({
    required this.weather,
    required this.scenario,
    required this.tips,
    required this.cargo,
  });
}

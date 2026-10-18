/// Deterministic, rule-based core of Weather-Smart Driver Tips.
///
/// Phase A (mock) uses all of it with a sample forecast. In Phase B the
/// same [buildTipDrafts] becomes the fallback when Gemini is unavailable,
/// fed by the real Open-Meteo forecast — so keep it pure and tested.
library;

import 'driver_tips_models.dart';

/// Thresholds, shared by mock and (later) real forecasts.
const rainThreshold = 60; // % chance
const heatThresholdC = 33.0;
const windThresholdKmh = 35.0;
const maxTips = 5;

/// Working day shown in the forecast strip (local hours).
const dayStartHour = 6;
const dayEndHour = 20;

const _leafyKeywords = [
  'cabbage',
  'lettuce',
  'leek',
  'spinach',
  'kale',
  'gotukola',
  'gotu kola',
  'kankun',
  'mukunuwenna',
  'greens',
  'salad',
  'coriander',
  'mint',
  'spring onion',
  'herb',
  'beans',
];

const _delicateKeywords = [
  'tomato',
  'banana',
  'papaya',
  'mango',
  'strawberr',
  'rambutan',
  'mangosteen',
  'guava',
  'avocado',
  'grape',
  'passion',
  'pepper',
];

enum CropKind { leafy, delicate, hardy }

CropKind classifyCrop(String name) {
  final n = name.toLowerCase();
  if (_leafyKeywords.any(n.contains)) return CropKind.leafy;
  if (_delicateKeywords.any(n.contains)) return CropKind.delicate;
  return CropKind.hardy;
}

/// Minimal view of a stop, so this file doesn't depend on DriverStop.
typedef StopCargo = ({bool isPickup, bool isDone, String? cropNames});

/// Crops still on the route today (done stops excluded), de-duplicated in
/// first-seen order. `cropNames` is the RPC's "Tomato, Carrot" string.
CargoProfile cargoFromStops(List<StopCargo> stops) {
  final pending = stops.where((s) => !s.isDone).toList();
  final crops = <String>[];
  for (final stop in pending) {
    for (final raw in (stop.cropNames ?? '').split(',')) {
      final name = raw.trim();
      if (name.isNotEmpty && !crops.contains(name)) crops.add(name);
    }
  }
  return CargoProfile(
    crops: crops,
    leafy: crops.where((c) => classifyCrop(c) == CropKind.leafy).toList(),
    delicate: crops.where((c) => classifyCrop(c) == CropKind.delicate).toList(),
    pendingPickups: pending.where((s) => s.isPickup).length,
    pendingStops: pending.length,
  );
}

/// Demo cargo for presentations when the driver has no stops.
const sampleCargo = CargoProfile(
  crops: ['Tomato', 'Cabbage', 'Carrot', 'Banana'],
  leafy: ['Cabbage'],
  delicate: ['Tomato', 'Banana'],
  pendingPickups: 3,
  pendingStops: 6,
  isSample: true,
);

/// "Automatic" scenario: rotates by day of year so it's stable for a
/// whole day but varies across days (the mock never looks frozen).
WeatherScenario scenarioForDay(DateTime day) {
  final dayOfYear = day.difference(DateTime(day.year)).inDays;
  return WeatherScenario.values[dayOfYear % WeatherScenario.values.length];
}

/// Sample hourly forecast for a scenario, [dayStartHour]..[dayEndHour].
/// Fully deterministic (no randomness), so screenshots and tests repeat.
WeatherSummary mockWeatherFor(WeatherScenario scenario) {
  HourlyWeather at(int hour) {
    final t = (hour - dayStartHour) / (dayEndHour - dayStartHour); // 0..1
    final midday = 1 - ((t - 0.55).abs() * 2).clamp(0.0, 1.0); // peak ~2pm
    return switch (scenario) {
      WeatherScenario.rainyAfternoon => HourlyWeather(
        hour: hour,
        rainProbability: hour < 13 ? 10 + hour : (hour <= 17 ? 80 : 45),
        temperatureC: 27 + 3 * midday,
        windKmh: hour >= 13 && hour <= 17 ? 24 : 14,
      ),
      WeatherScenario.hotDry => HourlyWeather(
        hour: hour,
        rainProbability: 5,
        temperatureC: 28 + 7 * midday, // peaks at 35
        windKmh: 10,
      ),
      WeatherScenario.clearMild => HourlyWeather(
        hour: hour,
        rainProbability: 10,
        temperatureC: 26 + 4 * midday,
        windKmh: 12,
      ),
      WeatherScenario.windy => HourlyWeather(
        hour: hour,
        rainProbability: 25,
        temperatureC: 27 + 2 * midday,
        windKmh: 22 + 20 * midday, // peaks at 42
      ),
    };
  }

  return WeatherSummary(
    hours: [for (var h = dayStartHour; h <= dayEndHour; h++) at(h)],
    isSample: true,
  );
}

/// The first..last hour at/above [threshold], or null.
({int from, int to})? _window(
  List<HourlyWeather> hours,
  bool Function(HourlyWeather) hit,
) {
  final hits = hours.where(hit).map((h) => h.hour).toList();
  if (hits.isEmpty) return null;
  return (from: hits.first, to: hits.last + 1);
}

/// Turns weather + cargo into at most [maxTips] tips, most severe first.
/// [formatHour] renders an hour (e.g. 13 → "1 PM"); injected so this stays
/// locale-free and testable.
List<TipDraft> buildTipDrafts(
  WeatherSummary weather,
  CargoProfile cargo, {
  String Function(int hour)? formatHour,
}) {
  final fmt = formatHour ?? (h) => '$h:00';
  final tips = <TipDraft>[];
  String crops(List<String> list) => list.join(', ');

  final rain = _window(
    weather.hours,
    (h) => h.rainProbability >= rainThreshold,
  );
  if (rain != null) {
    final window = '${fmt(rain.from)}–${fmt(rain.to)}';
    tips.add(
      TipDraft(
        id: 'rain',
        severity: TipSeverity.warning,
        titleKey: 'tip_rain_title',
        bodyKey: 'tip_rain_body',
        args: {'window': window, 'chance': '${weather.maxRainProbability}'},
        timeWindow: window,
      ),
    );
    if (cargo.leafy.isNotEmpty) {
      tips.add(
        TipDraft(
          id: 'rain_leafy',
          severity: TipSeverity.caution,
          titleKey: 'tip_rain_leafy_title',
          bodyKey: 'tip_rain_leafy_body',
          args: {'crops': crops(cargo.leafy)},
          relatedCrops: cargo.leafy,
        ),
      );
    }
    if (cargo.pendingPickups > 0) {
      tips.add(
        TipDraft(
          id: 'rain_pickups',
          severity: TipSeverity.caution,
          titleKey: 'tip_rain_pickups_title',
          bodyKey: 'tip_rain_pickups_body',
          args: {'count': '${cargo.pendingPickups}', 'time': fmt(rain.from)},
          timeWindow: window,
        ),
      );
    }
  }

  if (weather.maxTemperatureC >= heatThresholdC) {
    final hot = _window(weather.hours, (h) => h.temperatureC >= heatThresholdC);
    tips.add(
      TipDraft(
        id: 'heat',
        severity: TipSeverity.caution,
        titleKey: 'tip_heat_title',
        bodyKey: 'tip_heat_body',
        args: {'temp': weather.maxTemperatureC.round().toString()},
        timeWindow: hot == null ? null : '${fmt(hot.from)}–${fmt(hot.to)}',
      ),
    );
    if (cargo.delicate.isNotEmpty) {
      tips.add(
        TipDraft(
          id: 'heat_delicate',
          severity: TipSeverity.caution,
          titleKey: 'tip_heat_delicate_title',
          bodyKey: 'tip_heat_delicate_body',
          args: {'crops': crops(cargo.delicate)},
          relatedCrops: cargo.delicate,
        ),
      );
    }
    if (cargo.leafy.isNotEmpty) {
      tips.add(
        TipDraft(
          id: 'heat_leafy',
          severity: TipSeverity.info,
          titleKey: 'tip_heat_leafy_title',
          bodyKey: 'tip_heat_leafy_body',
          args: {'crops': crops(cargo.leafy)},
          relatedCrops: cargo.leafy,
        ),
      );
    }
  }

  if (weather.maxWindKmh >= windThresholdKmh) {
    tips.add(
      TipDraft(
        id: 'wind',
        severity: TipSeverity.caution,
        titleKey: 'tip_wind_title',
        bodyKey: 'tip_wind_body',
        args: {'speed': weather.maxWindKmh.round().toString()},
      ),
    );
  }

  if (tips.isEmpty) {
    tips.add(
      const TipDraft(
        id: 'clear',
        severity: TipSeverity.info,
        titleKey: 'tip_clear_title',
        bodyKey: 'tip_clear_body',
      ),
    );
  }

  if (cargo.pendingStops >= 4) {
    tips.add(
      TipDraft(
        id: 'route_order',
        severity: TipSeverity.info,
        titleKey: 'tip_route_order_title',
        bodyKey: 'tip_route_order_body',
        args: {'count': '${cargo.pendingStops}'},
      ),
    );
  }

  // Stable: most severe first, rule order within a severity.
  final ordered = [
    for (final s in TipSeverity.values.reversed)
      ...tips.where((t) => t.severity == s),
  ];
  return ordered.take(maxTips).toList();
}

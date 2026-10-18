import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/driver_stop.dart';
import 'driver_tip_rules.dart';
import 'driver_tips_models.dart';

/// Weather-Smart Driver Tips: today's practical tips from the forecast
/// along the route plus the cargo on board.
///
/// Phase A ships only [MockDriverTipsService]. Phase B adds a real one
/// (Open-Meteo + a Gemini Edge Function) behind this same interface, with
/// the rule-based mock logic kept as its fallback.
abstract class DriverTipsService {
  Future<DriverTipsResult> tipsFor({
    required DateTime day,
    required List<DriverStop> stops,
    required String languageCode,
    WeatherScenario? scenario,
    bool sampleCargoWhenEmpty = false,
  });
}

/// Sample forecast (by [scenario], else rotating per day) + the *real*
/// cargo from today's stops, run through the deterministic rules — so the
/// tips change with what's actually on the truck, never look frozen, and
/// no network is touched.
class MockDriverTipsService implements DriverTipsService {
  final Duration delay;

  const MockDriverTipsService({this.delay = const Duration(milliseconds: 700)});

  @override
  Future<DriverTipsResult> tipsFor({
    required DateTime day,
    required List<DriverStop> stops,
    required String languageCode,
    WeatherScenario? scenario,
    bool sampleCargoWhenEmpty = false,
  }) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);

    final effectiveScenario = scenario ?? scenarioForDay(day);
    final weather = mockWeatherFor(effectiveScenario);
    var cargo = cargoFromStops([
      for (final s in stops)
        (
          isPickup: s.type == DriverStopType.pickup,
          isDone: s.isDone,
          cropNames: s.cropNames,
        ),
    ]);
    if (cargo.isEmpty && sampleCargoWhenEmpty) cargo = sampleCargo;

    final hourFormat = DateFormat.j(languageCode);
    final drafts = cargo.isEmpty
        ? const <TipDraft>[]
        : buildTipDrafts(
            weather,
            cargo,
            formatHour: (h) =>
                hourFormat.format(DateTime(day.year, day.month, day.day, h)),
          );

    return DriverTipsResult(
      weather: weather,
      scenario: effectiveScenario,
      cargo: cargo,
      tips: [
        for (final d in drafts)
          DriverTip(
            id: d.id,
            severity: d.severity,
            title: d.titleKey.tr(namedArgs: d.args),
            body: d.bodyKey.tr(namedArgs: d.args),
            timeWindow: d.timeWindow,
            relatedCrops: d.relatedCrops,
          ),
      ],
    );
  }
}

/// Only the mock exists in Phase A; `DRIVER_TIPS_MODE=real` will select
/// the real service once it's built.
final driverTipsServiceProvider = Provider<DriverTipsService>(
  (_) => const MockDriverTipsService(),
);

// --- Demo controls -----------------------------------------------------------

/// Presenter controls for the sample forecast. Persisted so a chosen
/// scenario survives an app restart mid-demo.
class DriverTipsDemoState {
  /// null = automatic (rotates per day).
  final WeatherScenario? scenario;
  final bool sampleCargo;

  const DriverTipsDemoState({this.scenario, this.sampleCargo = false});
}

class DriverTipsDemoNotifier extends Notifier<DriverTipsDemoState> {
  static const _scenarioKey = 'driver_tips_demo_scenario';
  static const _sampleCargoKey = 'driver_tips_demo_sample_cargo';

  @override
  DriverTipsDemoState build() {
    _load();
    return const DriverTipsDemoState();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_scenarioKey);
    state = DriverTipsDemoState(
      scenario: WeatherScenario.values.where((s) => s.name == name).firstOrNull,
      sampleCargo: prefs.getBool(_sampleCargoKey) ?? false,
    );
  }

  Future<void> setScenario(WeatherScenario? scenario) async {
    state = DriverTipsDemoState(
      scenario: scenario,
      sampleCargo: state.sampleCargo,
    );
    final prefs = await SharedPreferences.getInstance();
    if (scenario == null) {
      await prefs.remove(_scenarioKey);
    } else {
      await prefs.setString(_scenarioKey, scenario.name);
    }
  }

  Future<void> setSampleCargo(bool value) async {
    state = DriverTipsDemoState(scenario: state.scenario, sampleCargo: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_sampleCargoKey, value);
  }
}

final driverTipsDemoProvider =
    NotifierProvider<DriverTipsDemoNotifier, DriverTipsDemoState>(
      DriverTipsDemoNotifier.new,
    );

// --- "Got it" dismissals (per day) -------------------------------------------

/// Tips the driver dismissed today. Keyed by date so tomorrow starts fresh.
class DismissedTipsStore {
  const DismissedTipsStore();

  String _key(DateTime day) =>
      'driver_tips_dismissed_${day.year}-${day.month}-${day.day}';

  Future<Set<String>> load(DateTime day) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_key(day)) ?? const []).toSet();
  }

  Future<void> save(DateTime day, Set<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key(day), ids.toList());
  }
}

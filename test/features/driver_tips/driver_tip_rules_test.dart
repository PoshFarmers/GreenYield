import 'package:flutter_test/flutter_test.dart';
import 'package:greenyield/features/driver_tips/driver_tip_rules.dart';
import 'package:greenyield/features/driver_tips/driver_tips_models.dart';

List<String> _ids(List<TipDraft> tips) => tips.map((t) => t.id).toList();

const _mixedCargo = CargoProfile(
  crops: ['Tomato', 'Cabbage', 'Carrot'],
  leafy: ['Cabbage'],
  delicate: ['Tomato'],
  pendingPickups: 2,
  pendingStops: 3,
);

void main() {
  group('classifyCrop', () {
    test('sorts crops into leafy / delicate / hardy', () {
      expect(classifyCrop('Cabbage'), CropKind.leafy);
      expect(classifyCrop('Gotu Kola'), CropKind.leafy);
      expect(classifyCrop('Tomato'), CropKind.delicate);
      expect(classifyCrop('Red bell pepper'), CropKind.delicate);
      expect(classifyCrop('Carrot'), CropKind.hardy);
    });
  });

  group('cargoFromStops', () {
    test('splits RPC crop strings, de-dupes, ignores finished stops', () {
      final cargo = cargoFromStops([
        (isPickup: true, isDone: false, cropNames: 'Tomato, Cabbage'),
        (isPickup: false, isDone: false, cropNames: 'Tomato,Carrot'),
        (isPickup: true, isDone: true, cropNames: 'Banana'),
      ]);
      expect(cargo.crops, ['Tomato', 'Cabbage', 'Carrot']);
      expect(cargo.leafy, ['Cabbage']);
      expect(cargo.delicate, ['Tomato']);
      expect(cargo.pendingPickups, 1);
      expect(cargo.pendingStops, 2);
    });

    test('no pending stops means empty cargo', () {
      expect(cargoFromStops([]).isEmpty, isTrue);
    });
  });

  group('mock weather', () {
    test('is deterministic', () {
      final a = mockWeatherFor(WeatherScenario.hotDry);
      final b = mockWeatherFor(WeatherScenario.hotDry);
      expect(
        a.hours.map((h) => h.temperatureC),
        b.hours.map((h) => h.temperatureC),
      );
      expect(a.isSample, isTrue);
    });

    test('scenario is stable within a day and varies across days', () {
      final morning = scenarioForDay(DateTime(2026, 10, 18, 7));
      final evening = scenarioForDay(DateTime(2026, 10, 18, 21));
      expect(morning, evening);
      final week = {
        for (var d = 0; d < 4; d++) scenarioForDay(DateTime(2026, 10, 18 + d)),
      };
      expect(week.length, WeatherScenario.values.length);
    });
  });

  group('buildTipDrafts', () {
    test('rainy afternoon: rain warning first, then cargo-specific tips', () {
      final tips = buildTipDrafts(
        mockWeatherFor(WeatherScenario.rainyAfternoon),
        _mixedCargo,
        formatHour: (h) => '$h',
      );
      expect(_ids(tips), ['rain', 'rain_leafy', 'rain_pickups']);
      expect(tips.first.severity, TipSeverity.warning);
      expect(tips.first.args['window'], '13–18');
      expect(tips[2].args['time'], '13');
    });

    test('hot day: heat + delicate-first + keep-greens-cool', () {
      final ids = _ids(
        buildTipDrafts(mockWeatherFor(WeatherScenario.hotDry), _mixedCargo),
      );
      expect(ids, containsAll(['heat', 'heat_delicate', 'heat_leafy']));
      expect(ids, isNot(contains('rain')));
    });

    test('windy day: wind tip', () {
      final ids = _ids(
        buildTipDrafts(mockWeatherFor(WeatherScenario.windy), _mixedCargo),
      );
      expect(ids, contains('wind'));
    });

    test('clear day with hardy cargo: single all-clear tip', () {
      const hardy = CargoProfile(
        crops: ['Carrot'],
        leafy: [],
        delicate: [],
        pendingPickups: 0,
        pendingStops: 1,
      );
      final ids = _ids(
        buildTipDrafts(mockWeatherFor(WeatherScenario.clearMild), hardy),
      );
      expect(ids, ['clear']);
    });

    test('cargo tips only appear when that cargo is on board', () {
      const hardy = CargoProfile(
        crops: ['Carrot'],
        leafy: [],
        delicate: [],
        pendingPickups: 0,
        pendingStops: 1,
      );
      final ids = _ids(
        buildTipDrafts(mockWeatherFor(WeatherScenario.rainyAfternoon), hardy),
      );
      expect(ids, ['rain']);
    });

    test('never more than maxTips, most severe first', () {
      final tips = buildTipDrafts(
        mockWeatherFor(WeatherScenario.rainyAfternoon),
        sampleCargo,
      );
      expect(tips.length, lessThanOrEqualTo(maxTips));
      for (var i = 1; i < tips.length; i++) {
        expect(
          tips[i - 1].severity.index,
          greaterThanOrEqualTo(tips[i].severity.index),
        );
      }
    });
  });
}

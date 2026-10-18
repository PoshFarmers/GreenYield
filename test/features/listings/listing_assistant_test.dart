import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:greenyield/features/listings/assistant/listing_assistant.dart';
import 'package:greenyield/models/farmer_profile.dart';

const _carrot = FarmerCrop(
  cropId: 'c-carrot',
  cropName: 'Carrot',
  category: 'vegetable',
);
const _tomato = FarmerCrop(
  cropId: 'c-tomato',
  cropName: 'Tomato',
  category: 'vegetable',
);

final _bytes = Uint8List.fromList([0xFF, 0xD8, 0xFF]);

const _mock = MockListingAssistant(describe: _describe, delay: Duration.zero);
String _describe(String crop) => 'Fresh $crop';

/// Real assistant stub: returns [result] or throws [error].
class _StubAssistant implements ListingAssistant {
  final ListingSuggestion? result;
  final Object? error;
  _StubAssistant({this.result, this.error});

  @override
  Future<ListingSuggestion> suggest(
    Uint8List imageBytes, {
    required String languageCode,
    required List<FarmerCrop> crops,
  }) async {
    if (error != null) throw error!;
    return result!;
  }
}

void main() {
  group('MockListingAssistant', () {
    test('prefers Tomato when the farmer grows it', () {
      expect(MockListingAssistant.pickCrop([_carrot, _tomato]), _tomato);
    });

    test("falls back to the first crop when there's no Tomato", () {
      expect(MockListingAssistant.pickCrop([_carrot]), _carrot);
    });

    test('suggests nothing when the farmer has no crops', () async {
      final s = await _mock.suggest(_bytes, languageCode: 'en', crops: []);
      expect(s.cropId, isNull);
      expect(s.confidence, 0);
    });

    test('is deterministic and ignores the photo', () async {
      final a = await _mock.suggest(
        _bytes,
        languageCode: 'en',
        crops: [_tomato],
      );
      final b = await _mock.suggest(
        Uint8List.fromList([1, 2, 3, 4]),
        languageCode: 'en',
        crops: [_tomato],
      );
      expect(a.cropId, b.cropId);
      expect(a.description, 'Fresh Tomato');
      expect(a.source, SuggestionSource.sample);
    });
  });

  group('FallbackListingAssistant', () {
    test('passes a real AI suggestion straight through', () async {
      const ai = ListingSuggestion(
        cropId: 'c-carrot',
        confidence: 0.9,
        description: 'Bright orange carrots',
        source: SuggestionSource.ai,
      );
      final s = await FallbackListingAssistant(
        real: _StubAssistant(result: ai),
        fallback: _mock,
      ).suggest(_bytes, languageCode: 'en', crops: [_carrot, _tomato]);
      expect(s, same(ai));
    });

    test(
      'returns the sample with the error code when the real call fails',
      () async {
        final s = await FallbackListingAssistant(
          real: _StubAssistant(
            error: const ListingAssistantException('daily_cap'),
          ),
          fallback: _mock,
        ).suggest(_bytes, languageCode: 'en', crops: [_tomato]);
        expect(s.source, SuggestionSource.sample);
        expect(s.fallbackReason, 'daily_cap');
        expect(s.cropId, 'c-tomato');
      },
    );

    test('maps unexpected errors to upstream_error', () async {
      final s = await FallbackListingAssistant(
        real: _StubAssistant(error: StateError('boom')),
        fallback: _mock,
      ).suggest(_bytes, languageCode: 'en', crops: [_tomato]);
      expect(s.fallbackReason, 'upstream_error');
    });

    test('reports disabled in mock mode without calling anything', () async {
      final s = await const FallbackListingAssistant(
        real: null,
        fallback: _mock,
      ).suggest(_bytes, languageCode: 'en', crops: [_tomato]);
      expect(s.fallbackReason, 'disabled');
    });
  });

  group('parseAiSuggestion', () {
    test('accepts a crop the farmer grows and clamps confidence', () {
      final s = parseAiSuggestion(
        {
          'crop_id': 'c-carrot',
          'confidence': 1.7,
          'description': '  Crisp carrots  ',
        },
        [_carrot],
      );
      expect(s.cropId, 'c-carrot');
      expect(s.confidence, 1.0);
      expect(s.description, 'Crisp carrots');
      expect(s.isAiGenerated, isTrue);
    });

    test('drops unknown or foreign crop ids and zeroes confidence', () {
      final s = parseAiSuggestion(
        {
          'crop_id': 'unknown',
          'confidence': 0.95,
          'description': 'A photo of a cat',
        },
        [_carrot],
      );
      expect(s.cropId, isNull);
      expect(s.confidence, 0);
      expect(s.isConfident, isFalse);
    });

    test('tolerates missing / wrongly-typed fields', () {
      final s = parseAiSuggestion({'crop_id': 42}, [_carrot]);
      expect(s.cropId, isNull);
      expect(s.description, '');
    });

    test('low confidence is not treated as confident', () {
      final s = parseAiSuggestion(
        {'crop_id': 'c-carrot', 'confidence': 0.3, 'description': ''},
        [_carrot],
      );
      expect(s.isConfident, isFalse);
    });
  });
}

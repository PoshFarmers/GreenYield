import 'dart:typed_data';

import '../../../models/farmer_profile.dart';

/// Where a suggestion came from — shown to the farmer, so AI output is
/// always labelled and a fallback is never passed off as AI.
enum SuggestionSource { ai, sample }

/// Why the real assistant wasn't used (null for real AI results). Mirrors
/// the `suggest-listing` Edge Function's error codes, plus client-side
/// ones (`offline`, `disabled`, `timeout`).
typedef FallbackReason = String;

class ListingSuggestion {
  /// One of the farmer's own crops, or null when the photo couldn't be
  /// matched — the UI then asks the farmer to choose.
  final String? cropId;

  /// 0..1. Below [lowConfidence] the UI asks the farmer to double-check.
  final double confidence;
  final String description;
  final SuggestionSource source;
  final FallbackReason? fallbackReason;

  static const lowConfidence = 0.5;

  const ListingSuggestion({
    required this.cropId,
    required this.confidence,
    required this.description,
    required this.source,
    this.fallbackReason,
  });

  bool get isAiGenerated => source == SuggestionSource.ai;
  bool get isConfident => cropId != null && confidence >= lowConfidence;
}

/// Error from a real assistant, carrying a machine-readable [code].
class ListingAssistantException implements Exception {
  final String code;
  const ListingAssistantException(this.code);

  @override
  String toString() => 'ListingAssistantException($code)';
}

/// "Snap to List": suggest the crop and a short description from a photo.
abstract class ListingAssistant {
  Future<ListingSuggestion> suggest(
    Uint8List imageBytes, {
    required String languageCode,
    required List<FarmerCrop> crops,
  });
}

/// Offline, deterministic stand-in: after a short "thinking" delay it
/// always suggests Tomato (or, if the farmer doesn't grow it, their first
/// crop) with a fixed description — whatever the photo shows.
class MockListingAssistant implements ListingAssistant {
  /// Builds the description for the chosen crop name. Injected so the
  /// pure logic stays testable; the app passes a translated template.
  final String Function(String cropName) describe;
  final Duration delay;

  const MockListingAssistant({
    required this.describe,
    this.delay = const Duration(milliseconds: 1200),
  });

  static const preferredCropName = 'Tomato';

  /// The crop the mock picks: Tomato if on the farmer's menu, else the
  /// first crop, else none.
  static FarmerCrop? pickCrop(List<FarmerCrop> crops) {
    for (final crop in crops) {
      if (crop.cropName.toLowerCase() == preferredCropName.toLowerCase()) {
        return crop;
      }
    }
    return crops.isEmpty ? null : crops.first;
  }

  @override
  Future<ListingSuggestion> suggest(
    Uint8List imageBytes, {
    required String languageCode,
    required List<FarmerCrop> crops,
  }) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    final crop = pickCrop(crops);
    return ListingSuggestion(
      cropId: crop?.cropId,
      confidence: crop == null ? 0 : 0.92,
      description: crop == null ? '' : describe(crop.cropName),
      source: SuggestionSource.sample,
    );
  }
}

/// Tries [real]; on *any* failure returns [fallback]'s suggestion, tagged
/// with the reason — so the farmer always gets a usable (clearly
/// labelled) result and the manual flow is never blocked.
class FallbackListingAssistant implements ListingAssistant {
  final ListingAssistant? real;
  final MockListingAssistant fallback;

  /// null [real] = mock mode (feature flag), reported as `disabled`.
  const FallbackListingAssistant({required this.real, required this.fallback});

  @override
  Future<ListingSuggestion> suggest(
    Uint8List imageBytes, {
    required String languageCode,
    required List<FarmerCrop> crops,
  }) async {
    FallbackReason reason = 'disabled';
    final real = this.real;
    if (real != null) {
      try {
        return await real.suggest(
          imageBytes,
          languageCode: languageCode,
          crops: crops,
        );
      } on ListingAssistantException catch (e) {
        reason = e.code;
      } catch (_) {
        reason = 'upstream_error';
      }
    }
    final sample = await fallback.suggest(
      imageBytes,
      languageCode: languageCode,
      crops: crops,
    );
    return ListingSuggestion(
      cropId: sample.cropId,
      confidence: sample.confidence,
      description: sample.description,
      source: SuggestionSource.sample,
      fallbackReason: reason,
    );
  }
}

/// Validates a raw Edge Function response against the farmer's crops:
/// unknown ids become null, confidence is clamped to 0..1 (and 0 when no
/// crop matched), description is trimmed.
ListingSuggestion parseAiSuggestion(
  Map<String, dynamic> json,
  List<FarmerCrop> crops,
) {
  final rawId = json['crop_id'];
  final cropId = rawId is String && crops.any((c) => c.cropId == rawId)
      ? rawId
      : null;
  final rawConfidence = json['confidence'];
  final confidence = cropId == null
      ? 0.0
      : (rawConfidence is num ? rawConfidence.toDouble() : 0.0).clamp(0.0, 1.0);
  final description = json['description'] is String
      ? (json['description'] as String).trim()
      : '';
  return ListingSuggestion(
    cropId: cropId,
    confidence: confidence,
    description: description,
    source: SuggestionSource.ai,
  );
}

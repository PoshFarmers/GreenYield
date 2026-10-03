import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/supabase/client.dart';
import '../../../models/farmer_profile.dart';
import 'listing_assistant.dart';

/// Real Snap-to-List: sends the photo to the `suggest-listing` Edge
/// Function, which calls Gemini with the key held as a Supabase secret.
/// Throws [ListingAssistantException] on any failure; callers wrap it in
/// [FallbackListingAssistant].
class GeminiListingAssistant implements ListingAssistant {
  static const _function = 'suggest-listing';
  static const _timeout = Duration(seconds: 25);

  /// The function rejects bigger payloads; don't waste the upload.
  static const maxImageBytes = 1500 * 1024;

  const GeminiListingAssistant();

  @override
  Future<ListingSuggestion> suggest(
    Uint8List imageBytes, {
    required String languageCode,
    required List<FarmerCrop> crops,
  }) async {
    if (crops.isEmpty) throw const ListingAssistantException('no_crops');
    if (imageBytes.lengthInBytes > maxImageBytes) {
      throw const ListingAssistantException('image_too_large');
    }

    try {
      final response = await supabase.functions
          .invoke(
            _function,
            body: {
              'image_base64': base64Encode(imageBytes),
              'mime_type': _sniffMimeType(imageBytes),
              'language': languageCode,
            },
          )
          .timeout(_timeout);
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw const ListingAssistantException('invalid_output');
      }
      return parseAiSuggestion(data, crops);
    } on FunctionException catch (e) {
      final details = e.details;
      final code = details is Map && details['error'] is String
          ? details['error'] as String
          : (e.status == 404 ? 'not_deployed' : 'upstream_error');
      throw ListingAssistantException(code);
    } on TimeoutException {
      throw const ListingAssistantException('timeout');
    } on ListingAssistantException {
      rethrow;
    } catch (e) {
      final raw = e.toString();
      final offline =
          raw.contains('SocketException') ||
          raw.contains('Failed host lookup') ||
          raw.contains('ClientException');
      throw ListingAssistantException(offline ? 'offline' : 'upstream_error');
    }
  }

  /// image_picker returns JPEG for camera/most gallery picks, but PNG and
  /// WebP do occur; Gemini needs the right type.
  static String _sniffMimeType(Uint8List b) {
    if (b.length > 4 && b[0] == 0x89 && b[1] == 0x50) return 'image/png';
    if (b.length > 12 && b[8] == 0x57 && b[9] == 0x45) return 'image/webp';
    return 'image/jpeg';
  }
}

/// Snap-to-List as configured: real Gemini (with sample fallback) unless
/// `AI_ASSISTANT_MODE=mock`, in which case it never touches the network.
final listingAssistantProvider = Provider<ListingAssistant>((ref) {
  final mode = ref.watch(appConfigProvider).listingAssistantMode;
  return FallbackListingAssistant(
    real: mode == AiMode.real ? const GeminiListingAssistant() : null,
    fallback: MockListingAssistant(
      describe: (cropName) =>
          'snap_sample_description'.tr(namedArgs: {'crop': cropName}),
    ),
  );
});

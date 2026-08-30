import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Loads translations from several JSON files per locale and merges
/// them, instead of easy_localization's default one-file-per-locale.
class MultiFileAssetLoader extends AssetLoader {
  static const _files = [
    'common',
    'auth',
    'farmer',
    'buyer',
    'driver',
    'notifications',
    'listings',
    'marketplace',
    'cart',
  ];

  const MultiFileAssetLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    final merged = <String, dynamic>{};
    for (final file in _files) {
      final filePath = '$path/${locale.languageCode}/$file.json';
      try {
        final content = await rootBundle.loadString(filePath);
        merged.addAll(json.decode(content) as Map<String, dynamic>);
      } catch (_) {
        // Expected for now
      }
    }
    return merged;
  }
}

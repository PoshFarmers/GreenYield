// Uploads fallback_images/<category>/<CropName>.png to the
// `crop-fallback-images` storage bucket and upserts the corresponding
// `crop` row (creating it if it doesn't exist yet -- crop catalogue
// entries are data, not schema, so no migration is needed to add one).
//
// Run: dart run scripts/upload_crop_fallback_images.dart
//
// Requires SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in .env (the
// service-role key, NOT the publishable key already used by the app --
// this needs to bypass RLS to write to `crop` and the storage bucket).
// Get it from Supabase dashboard > Project Settings > API.

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Filenames to skip this run (e.g. crops not yet ready to publish).
const _exclude = {'Durian.png'};

const _bucket = 'crop-fallback-images';
const _imagesDir = 'fallback_images';

/// Minimal KEY=VALUE .env reader -- deliberately not using flutter_dotenv
/// here, since it pulls in package:flutter (needs Flutter's patched SDK,
/// dart:ui) and this script must run under plain `dart run`.
Map<String, String> _loadEnv(String path) {
  final env = <String, String>{};
  final file = File(path);
  if (!file.existsSync()) return env;
  for (final rawLine in file.readAsLinesSync()) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final separatorIndex = line.indexOf('=');
    if (separatorIndex == -1) continue;
    final key = line.substring(0, separatorIndex).trim();
    var value = line.substring(separatorIndex + 1).trim();
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      value = value.substring(1, value.length - 1);
    }
    env[key] = value;
  }
  return env;
}

Future<void> main() async {
  final env = _loadEnv('.env');
  final url = env['SUPABASE_URL'];
  final serviceRoleKey = env['SUPABASE_SERVICE_ROLE_KEY'];
  if (url == null || serviceRoleKey == null) {
    stderr.writeln('Missing SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY in .env');
    exit(1);
  }

  final headers = {
    'apikey': serviceRoleKey,
    'Authorization': 'Bearer $serviceRoleKey',
  };

  var uploaded = 0;
  var skipped = 0;

  final root = Directory(_imagesDir);
  if (!root.existsSync()) {
    stderr.writeln('No $_imagesDir directory found next to pubspec.yaml.');
    exit(1);
  }

  for (final categoryDir in root.listSync().whereType<Directory>()) {
    final category = categoryDir.path.split(Platform.pathSeparator).last;
    for (final file in categoryDir.listSync().whereType<File>()) {
      final fileName = file.path.split(Platform.pathSeparator).last;
      if (_exclude.contains(fileName)) {
        print('Skipping $fileName (excluded)');
        skipped++;
        continue;
      }
      if (!fileName.toLowerCase().endsWith('.png')) {
        skipped++;
        continue;
      }

      final cropName = fileName.substring(0, fileName.length - '.png'.length);

      try {
        final cropId = await _upsertCrop(
          url: url,
          headers: headers,
          name: cropName,
          category: category,
        );

        final bytes = await file.readAsBytes();
        final objectPath = '$cropId.png';
        await _uploadImage(
          url: url,
          headers: headers,
          objectPath: objectPath,
          bytes: bytes,
        );
        await _setFallbackImageUrl(
          url: url,
          headers: headers,
          cropId: cropId,
          imageUrl: objectPath,
        );

        print('Uploaded $cropName ($category) -> $objectPath');
        uploaded++;
      } catch (e) {
        stderr.writeln('Failed for $cropName: $e');
        skipped++;
      }
    }
  }

  print('\nDone. uploaded=$uploaded skipped=$skipped');
}

/// Returns the crop id, inserting the row if it doesn't exist yet.
/// Category is left untouched on conflict so a hand-edited category
/// isn't clobbered by a rerun.
Future<String> _upsertCrop({
  required String url,
  required Map<String, String> headers,
  required String name,
  required String category,
}) async {
  final existing = await http.get(
    Uri.parse(
      '$url/rest/v1/crop?select=id&name=eq.${Uri.encodeComponent(name)}',
    ),
    headers: headers,
  );
  final existingRows = jsonDecode(existing.body) as List;
  if (existingRows.isNotEmpty) {
    return existingRows.first['id'] as String;
  }

  final insertResponse = await http.post(
    Uri.parse('$url/rest/v1/crop'),
    headers: {
      ...headers,
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    },
    body: jsonEncode({'name': name, 'category': category}),
  );
  if (insertResponse.statusCode >= 300) {
    throw Exception('insert crop failed: ${insertResponse.body}');
  }
  final inserted = jsonDecode(insertResponse.body) as List;
  return inserted.first['id'] as String;
}

Future<void> _uploadImage({
  required String url,
  required Map<String, String> headers,
  required String objectPath,
  required List<int> bytes,
}) async {
  final response = await http.post(
    Uri.parse('$url/storage/v1/object/$_bucket/$objectPath'),
    headers: {...headers, 'Content-Type': 'image/png', 'x-upsert': 'true'},
    body: bytes,
  );
  if (response.statusCode >= 300) {
    throw Exception('upload failed: ${response.body}');
  }
}

Future<void> _setFallbackImageUrl({
  required String url,
  required Map<String, String> headers,
  required String cropId,
  required String imageUrl,
}) async {
  final response = await http.patch(
    Uri.parse('$url/rest/v1/crop?id=eq.$cropId'),
    headers: {...headers, 'Content-Type': 'application/json'},
    body: jsonEncode({'fallback_image_url': imageUrl}),
  );
  if (response.statusCode >= 300) {
    throw Exception('update crop failed: ${response.body}');
  }
}

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../../../../core/localization/multi_file_asset_loader.dart';
import '../../../../models/farmer_profile.dart';
import 'crop_details_sheet.dart';
import 'crop_tile.dart';

/// Preview harness for the crop fallback-image change: the onboarding
/// crop grid tile and the details sheet's fallback preview, without
/// needing a live Supabase/PowerSync connection (MediaImage swallows
/// the fetch failure and shows its placeholder when there's no network,
/// which is fine here since we only care about layout/wiring).
///
/// Run with: flutter widget-preview start
@Preview(name: 'Farmer crop grid + fallback image sheet')
Widget cropFallbackImagePreview() => const _PreviewApp();

class _PreviewApp extends StatefulWidget {
  const _PreviewApp();

  @override
  State<_PreviewApp> createState() => _PreviewAppState();
}

class _PreviewAppState extends State<_PreviewApp> {
  late final Future<void> _init;

  @override
  void initState() {
    super.initState();
    _init = EasyLocalization.ensureInitialized();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _init,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const MaterialApp(
            home: Scaffold(body: Center(child: CircularProgressIndicator())),
          );
        }
        return EasyLocalization(
          supportedLocales: const [Locale('en')],
          path: 'assets/translations',
          assetLoader: const MultiFileAssetLoader(),
          fallbackLocale: const Locale('en'),
          child: Builder(
            builder: (context) => MaterialApp(
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              home: const _CropPreviewScreen(),
            ),
          ),
        );
      },
    );
  }
}

const _sampleCrops = [
  Crop(
    id: 'preview-tomato',
    name: 'Tomato',
    category: 'vegetable',
    fallbackImageUrl: 'preview-tomato.png',
  ),
  Crop(id: 'preview-carrot', name: 'Carrot', category: 'vegetable'),
  Crop(
    id: 'preview-mango',
    name: 'Mango',
    category: 'fruit',
    fallbackImageUrl: 'preview-mango.png',
  ),
];

class _CropPreviewScreen extends StatefulWidget {
  const _CropPreviewScreen();

  @override
  State<_CropPreviewScreen> createState() => _CropPreviewScreenState();
}

class _CropPreviewScreenState extends State<_CropPreviewScreen> {
  String? _selectedCropId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crop fallback image preview')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: GridView.count(
          crossAxisCount: 3,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 0.95,
          children: _sampleCrops.map((crop) {
            return CropTile(
              crop: crop,
              isSelected: crop.id == _selectedCropId,
              onTap: () async {
                setState(() => _selectedCropId = crop.id);
                await showCropDetailsSheet(
                  context: context,
                  cropName: crop.name,
                  fallbackImageUrl: crop.fallbackImageUrl,
                );
              },
            );
          }).toList(),
        ),
      ),
    );
  }
}

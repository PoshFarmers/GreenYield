import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../../../core/auth/auth_providers.dart';
import '../../../../core/storage/crop_photo_service.dart';
import '../../../../core/widgets/avatar_image.dart';
import '../../../../core/widgets/media_image.dart';
import '../../../../models/farmer_profile.dart';
import '../../../../models/profile.dart';
import '../farmer_profile_service.dart';
import 'crop_details_sheet.dart';
import 'farmer_profile_edit_screen.dart';

class FarmerProfileViewScreen extends ConsumerStatefulWidget {
  final Profile? initialProfile;

  const FarmerProfileViewScreen({super.key, this.initialProfile});

  @override
  ConsumerState<FarmerProfileViewScreen> createState() =>
      _FarmerProfileViewScreenState();
}

class _FarmerProfileViewScreenState
    extends ConsumerState<FarmerProfileViewScreen> {
  final _service = FarmerProfileService();

  late final Stream<Profile?> _profileStream;
  late final Stream<FarmerProfile?> _farmerProfileStream;
  late final String _userId;

  @override
  void initState() {
    super.initState();
    _userId = ref.read(authServiceProvider).currentUser!.id;
    _profileStream = ref.read(authServiceProvider).watchOwnProfile();
    _farmerProfileStream = _service.watchOwnProfile(_userId);
  }

  /// Opens the shared photo/description/price editor for one crop and
  /// persists just that row. [existing] is null when adding a crop the
  /// farmer hasn't registered yet.
  Future<void> _editCrop({
    required String cropId,
    required String cropName,
    FarmerCrop? existing,
  }) async {
    final details = await showCropDetailsSheet(
      context: context,
      cropName: cropName,
      initialDescription: existing?.description,
      initialPrice: existing?.defaultPricePerKg,
      existingImagePath: existing?.imageUrl,
      onRemove: existing == null
          ? null
          : () => _service.removeCrop(_userId, cropId),
    );
    if (details == null) return;

    // Keep the stored path when no new photo was picked, so editing the
    // price doesn't silently drop the existing image.
    var imageUrl = existing?.imageUrl;
    if (details.imageBytes != null) {
      imageUrl = await CropPhotoService().upload(
        userId: _userId,
        cropId: cropId,
        bytes: details.imageBytes!,
        fileName: details.imageFileName ?? 'photo.jpg',
      );
    }

    await _service.upsertCrop(
      _userId,
      FarmerCropInput(
        cropId: cropId,
        description: details.description,
        defaultPricePerKg: details.price,
        imageUrl: imageUrl,
      ),
    );
  }

  /// Lets the farmer pick from catalogue crops they haven't registered
  /// yet, then drops straight into the details editor for it.
  Future<void> _addCrop(List<FarmerCrop> registered) async {
    final registeredIds = registered.map((c) => c.cropId).toSet();

    final picked = await showModalBottomSheet<Crop>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StreamBuilder<List<Crop>>(
        stream: _service.watchAllCrops(),
        builder: (context, snapshot) {
          final available = (snapshot.data ?? [])
              .where((c) => !registeredIds.contains(c.id))
              .toList();

          if (!snapshot.hasData) {
            return const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator()),
            );
          }

          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Text(
                    'add_crop'.tr(),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (available.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text('all_crops_added'.tr()),
                  ),
                for (final crop in available)
                  ListTile(
                    leading: Icon(
                      crop.category == 'fruit' ? Icons.apple : Icons.eco,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    title: Text(crop.name),
                    onTap: () => Navigator.of(sheetContext).pop(crop),
                  ),
              ],
            ),
          );
        },
      ),
    );

    if (picked == null || !mounted) return;
    await _editCrop(cropId: picked.id, cropName: picked.name);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('farmer_profile_title'.tr())),
      body: StreamBuilder<Profile?>(
        stream: _profileStream,
        initialData: widget.initialProfile,
        builder: (context, profileSnapshot) {
          if (!profileSnapshot.hasData && !profileSnapshot.hasError) {
            return const Center(child: CircularProgressIndicator());
          }
          if (profileSnapshot.hasError) {
            return Center(child: Text(profileSnapshot.error.toString()));
          }

          final profile = profileSnapshot.data;
          if (profile == null) {
            return const Center(child: Text('Profile not found'));
          }

          return StreamBuilder<FarmerProfile?>(
            stream: _farmerProfileStream,
            builder: (context, farmerSnapshot) {
              if (!farmerSnapshot.hasData && !farmerSnapshot.hasError) {
                return const Center(child: CircularProgressIndicator());
              }
              if (farmerSnapshot.hasError) {
                return Center(child: Text(farmerSnapshot.error.toString()));
              }

              final farmerProfile = farmerSnapshot.data;
              if (farmerProfile == null) {
                return const Center(child: Text('Farmer profile not found'));
              }

              return SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _HeaderCard(
                          profile: profile,
                          onEdit: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => FarmerProfileEditScreen(
                                genericProfile: profile,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const _WalletCard(),
                        const SizedBox(height: 12),
                        _FarmLocationCard(profile: profile),
                        const SizedBox(height: 12),
                        const _PerformanceCard(),
                        const SizedBox(height: 12),
                        _CropsGrownCard(
                          crops: farmerProfile.crops,
                          onTapCrop: (crop) => _editCrop(
                            cropId: crop.cropId,
                            cropName: crop.cropName,
                            existing: crop,
                          ),
                          onAddCrop: () => _addCrop(farmerProfile.crops),
                        ),
                        const SizedBox(height: 24),
                        OutlinedButton.icon(
                          onPressed: () =>
                              ref.read(authServiceProvider).signOut(),
                          icon: const Icon(Icons.logout),
                          label: Text('logout'.tr()),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Theme.of(context)
                                .colorScheme
                                .error,
                            side: BorderSide(
                              color: Theme.of(context).colorScheme.error,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Shared card chrome for every section on this screen.
class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _Card({required this.child, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: child,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SectionTitle({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          label,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final Profile profile;
  final VoidCallback onEdit;

  const _HeaderCard({required this.profile, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final createdAt = profile.createdAt;

    return _Card(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AvatarImage(path: profile.avatarUrl, radius: 36),
              const Spacer(),
              IconButton(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'edit_profile'.tr(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${profile.firstName} ${profile.lastName}',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          if (profile.locationText != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    profile.locationText!,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
          if (createdAt != null) ...[
            const SizedBox(height: 12),
            Chip(
              label: Text(
                '${'member_since'.tr()} ${createdAt.year}',
                style: theme.textTheme.bodySmall,
              ),
              visualDensity: VisualDensity.compact,
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ],
        ],
      ),
    );
  }
}

/// Wallet balance — the wallet feature itself isn't built yet, so this
/// shows a placeholder rather than a real balance.
class _WalletCard extends StatelessWidget {
  const _WalletCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Card(
      child: Row(
        children: [
          Icon(
            Icons.account_balance_wallet_outlined,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('wallet_balance'.tr(), style: theme.textTheme.bodySmall),
              const SizedBox(height: 2),
              Text(
                '—',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const Spacer(),
          Text('coming_soon'.tr(), style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _FarmLocationCard extends StatelessWidget {
  final Profile profile;

  const _FarmLocationCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    final point = profile.locationPoint;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(icon: Icons.map_outlined, label: 'farm_location'.tr()),
          const SizedBox(height: 12),
          if (point == null)
            Text('—', style: Theme.of(context).textTheme.bodyMedium)
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 160,
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: ll.LatLng(point.latitude, point.longitude),
                    initialZoom: 14,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.none,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.greenyield.app',
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: ll.LatLng(point.latitude, point.longitude),
                          width: 40,
                          height: 40,
                          child: Icon(
                            Icons.location_on,
                            size: 40,
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Sales/delivery/listing stats — none of these features exist yet, so
/// every value is a placeholder for now.
class _PerformanceCard extends StatelessWidget {
  const _PerformanceCard();

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(icon: Icons.bar_chart, label: 'performance'.tr()),
          const SizedBox(height: 12),
          _StatRow(label: 'total_sales'.tr()),
          const SizedBox(height: 8),
          _StatRow(label: 'on_time_delivery'.tr()),
          const SizedBox(height: 8),
          _StatRow(label: 'active_listings'.tr()),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;

  const _StatRow({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label.toUpperCase(), style: theme.textTheme.labelSmall),
          Text(
            '—',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _CropsGrownCard extends StatelessWidget {
  final List<FarmerCrop> crops;
  final ValueChanged<FarmerCrop> onTapCrop;
  final VoidCallback onAddCrop;

  const _CropsGrownCard({
    required this.crops,
    required this.onTapCrop,
    required this.onAddCrop,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _SectionTitle(
                icon: Icons.eco_outlined,
                label: 'crops_grown'.tr(),
              ),
              const Spacer(),
              if (crops.isNotEmpty)
                IconButton(
                  onPressed: onAddCrop,
                  icon: const Icon(Icons.add),
                  tooltip: 'add_crop'.tr(),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (crops.isEmpty) ...[
            Text('no_crops_yet'.tr(), style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: onAddCrop,
              icon: const Icon(Icons.add),
              label: Text('set_up_crops'.tr()),
            ),
          ] else ...[
            Text('tap_crop_to_edit'.tr(), style: theme.textTheme.bodySmall),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: crops
                  .map(
                    (crop) =>
                        _CropTile(crop: crop, onTap: () => onTapCrop(crop)),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

/// One crop on the farmer's menu: its photo, name and asking price.
/// Tapping opens the per-crop editor.
class _CropTile extends StatelessWidget {
  final FarmerCrop crop;
  final VoidCallback onTap;

  const _CropTile({required this.crop, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 148,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 36,
                width: 36,
                child: MediaImage(
                  path: crop.displayImage.path,
                  bucket: crop.displayImage.bucket,
                  public: crop.displayImage.isFallback,
                  placeholder: Container(
                    color: theme.colorScheme.surfaceContainerLowest,
                    child: Icon(
                      crop.category == 'fruit' ? Icons.apple : Icons.eco,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    crop.cropName,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    crop.defaultPricePerKg == null
                        ? '—'
                        : 'Rs ${crop.defaultPricePerKg!.toStringAsFixed(0)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

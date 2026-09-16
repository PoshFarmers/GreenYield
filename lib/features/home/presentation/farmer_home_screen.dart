import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

//import '../../../core/theme/theme_provider.dart';
import '../../../core/widgets/app_header.dart';
import '../../../models/farmer_profile.dart';
import '../../../models/produce_listing.dart';
import '../../../models/profile.dart';
import '../../listings/presentation/add_harvest_screen.dart';
import '../../listings/presentation/my_listings_screen.dart';
import '../../listings/produce_listing_service.dart';
import '../../pricing/presentation/widgets/crop_price_history_section.dart';
import '../../pricing/presentation/widgets/farmer_price_trends_section.dart';
import '../../profile/farmer/farmer_profile_service.dart';

/// Farmer's Home Screen
class FarmerHomeScreen extends ConsumerWidget {
  final Profile profile;

  const FarmerHomeScreen({super.key, required this.profile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    //final themeMode = ref.watch(themeModeProvider);
    final listingService = ProduceListingService();
    final farmerService = FarmerProfileService();

    return Scaffold(
      appBar: AppHeader(profile: profile),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: StreamBuilder<List<ProduceListing>>(
              stream: listingService.watchOwnListings(profile.id),
              builder: (context, listingSnapshot) {
                final listings = listingSnapshot.data ?? [];
                final active = listings
                    .where((l) => l.status == 'active')
                    .length;
                final soldOut = listings
                    .where((l) => l.status == 'sold_out')
                    .length;

                return ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      '${'welcome'.tr()}, ${profile.firstName}',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'farmer_home_subtitle'.tr(),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            icon: Icons.grass_outlined,
                            label: 'stat_active'.tr(),
                            value: '$active',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _StatCard(
                            icon: Icons.remove_shopping_cart_outlined,
                            label: 'stat_sold_out'.tr(),
                            value: '$soldOut',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    AddHarvestScreen(profile: profile),
                              ),
                            ),
                            icon: const Icon(Icons.add),
                            label: Text('add_harvest'.tr()),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    MyListingsScreen(profile: profile),
                              ),
                            ),
                            icon: const Icon(Icons.list_alt_outlined),
                            label: Text('my_listings_title'.tr()),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    FarmerPriceTrendsSection(farmerProfileId: profile.id),
                    const SizedBox(height: 28),
                    StreamBuilder<FarmerProfile?>(
                      stream: farmerService.watchOwnProfile(profile.id),
                      builder: (context, farmerSnapshot) {
                        final crops = farmerSnapshot.data?.crops ?? [];
                        return CropPriceHistorySection(crops: crops);
                      },
                    ),
                    // const SizedBox(height: 28),
                    // Text('settings'.tr(), style: theme.textTheme.labelLarge),
                    // const SizedBox(height: 8),
                    // SegmentedButton<ThemeMode>(
                    //   segments: const [
                    //     ButtonSegment(
                    //       value: ThemeMode.light,
                    //       label: Text('Light'),
                    //       icon: Icon(Icons.light_mode),
                    //     ),
                    //     ButtonSegment(
                    //       value: ThemeMode.dark,
                    //       label: Text('Dark'),
                    //       icon: Icon(Icons.dark_mode),
                    //     ),
                    //     ButtonSegment(
                    //       value: ThemeMode.system,
                    //       label: Text('System'),
                    //       icon: Icon(Icons.settings_suggest),
                    //     ),
                    //   ],
                    //   selected: {themeMode},
                    //   onSelectionChanged: (s) => ref
                    //       .read(themeModeProvider.notifier)
                    //       .setThemeMode(s.first),
                    // ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(height: 8),
          Text(label, style: theme.textTheme.bodySmall),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

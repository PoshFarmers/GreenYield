import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme_provider.dart';
import '../../../core/widgets/app_secondary_header.dart';
import '../../../core/widgets/media_image.dart';
import '../../../models/profile.dart';
import '../order_providers.dart';
import '../order_detail_models.dart';
import 'order_detail_screen.dart';
import 'widgets/order_status_chip.dart';

/// Sprint 3 — Driver: 3-tab Deliveries screen.
/// Tab 1: Pickup Requests (assigned, packed)
/// Tab 2: Active Deliveries (picked_up, in_transit)
/// Tab 3: Completed (delivered)
///
/// Responsive: a single column on phones, and a wrapping multi-column
/// layout on tablets/desktop (see [_ResponsiveDeliveryGrid]). Theme
/// (light/dark/system) and language can be changed right from this
/// screen's header via [_DeliverySettingsMenu], in addition to the
/// Home screen's controls.
class DriverDeliveriesScreen extends ConsumerStatefulWidget {
  final Profile profile;

  const DriverDeliveriesScreen({super.key, required this.profile});

  @override
  ConsumerState<DriverDeliveriesScreen> createState() =>
      _DriverDeliveriesScreenState();
}

class _DriverDeliveriesScreenState extends ConsumerState<DriverDeliveriesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profileId = widget.profile.id;

    return Scaffold(
      appBar: AppSecondaryHeader(
        title: 'deliveries_title'.tr(),
        showBackButton: false,
        actions: const [_DeliverySettingsMenu()],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: [
            Tab(text: 'tab_pickup_requests'.tr()),
            Tab(text: 'tab_active_deliveries'.tr()),
            Tab(text: 'tab_completed'.tr()),
          ],
          labelStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: const TextStyle(fontSize: 13),
          indicatorSize: TabBarIndicatorSize.tab,
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _DeliveryList(
            key: const ValueKey('driver_pickup'),
            provider: ref.watch(driverPickupRequestsProvider(profileId)),
            emptyMessage: 'empty_pickup_requests'.tr(),
            emptyIcon: Icons.storefront_outlined,
          ),
          _DeliveryList(
            key: const ValueKey('driver_active'),
            provider: ref.watch(driverActiveDeliveriesProvider(profileId)),
            emptyMessage: 'empty_active_deliveries'.tr(),
            emptyIcon: Icons.local_shipping_outlined,
          ),
          _DeliveryList(
            key: const ValueKey('driver_completed'),
            provider: ref.watch(driverCompletedDeliveriesProvider(profileId)),
            emptyMessage: 'empty_completed'.tr(),
            emptyIcon: Icons.task_alt_outlined,
          ),
        ],
      ),
    );
  }
}

/// Theme (light/dark/system) + language switcher, available inline on
/// this screen's header so a driver never has to leave Deliveries to
/// change either.
class _DeliverySettingsMenu extends ConsumerWidget {
  const _DeliverySettingsMenu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: 'settings'.tr(),
      icon: const Icon(Icons.tune),
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Text(
            'toggle_theme'.tr(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        _themeItem(context, ref, ThemeMode.light, Icons.light_mode, 'light'),
        _themeItem(context, ref, ThemeMode.dark, Icons.dark_mode, 'dark'),
        _themeItem(
          context,
          ref,
          ThemeMode.system,
          Icons.settings_suggest,
          'system',
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          enabled: false,
          child: Text(
            'language'.tr(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        for (final locale in context.supportedLocales)
          PopupMenuItem<String>(
            value: 'locale:${locale.languageCode}',
            child: Row(
              children: [
                if (context.locale == locale)
                  Icon(
                    Icons.check,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  )
                else
                  const SizedBox(width: 18),
                const SizedBox(width: 8),
                Text(_localeLabel(locale.languageCode)),
              ],
            ),
          ),
      ],
      onSelected: (value) {
        if (value.startsWith('locale:')) {
          final code = value.substring('locale:'.length);
          final locale = context.supportedLocales.firstWhere(
            (l) => l.languageCode == code,
          );
          context.setLocale(locale);
        } else if (value.startsWith('theme:')) {
          final mode = ThemeMode.values.firstWhere(
            (m) => m.name == value.substring('theme:'.length),
          );
          ref.read(themeModeProvider.notifier).setThemeMode(mode);
        }
      },
    );
  }

  PopupMenuItem<String> _themeItem(
    BuildContext context,
    WidgetRef ref,
    ThemeMode mode,
    IconData icon,
    String labelKey,
  ) {
    final selected = ref.watch(themeModeProvider) == mode;
    return PopupMenuItem<String>(
      value: 'theme:${mode.name}',
      child: Row(
        children: [
          if (selected)
            Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary)
          else
            Icon(icon, size: 18),
          const SizedBox(width: 8),
          Text(labelKey.tr()),
        ],
      ),
    );
  }

  String _localeLabel(String code) => switch (code) {
    'en' => 'English',
    'si' => 'සිංහල',
    'ta' => 'தமிழ்',
    _ => code.toUpperCase(),
  };
}

class _DeliveryList extends ConsumerWidget {
  final AsyncValue<List<DeliverySummary>> provider;
  final String emptyMessage;
  final IconData emptyIcon;

  const _DeliveryList({
    super.key,
    required this.provider,
    required this.emptyMessage,
    required this.emptyIcon,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return provider.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text(
          'error_loading_deliveries'.tr(namedArgs: {'error': '$e'}),
          textAlign: TextAlign.center,
        ),
      ),
      data: (deliveries) {
        if (deliveries.isEmpty) {
          final theme = Theme.of(context);
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    emptyIcon,
                    size: 52,
                    color: theme.colorScheme.outlineVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    emptyMessage,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return _ResponsiveDeliveryGrid(deliveries: deliveries);
      },
    );
  }
}

/// Lays [deliveries] out as a single column on narrow (phone) screens,
/// and as a wrapping multi-column grid as width grows (tablet/desktop/
/// web). Cards have variable height, so this uses [Wrap] rather than a
/// [GridView] — no need to force a fixed aspect ratio per tile.
class _ResponsiveDeliveryGrid extends StatelessWidget {
  final List<DeliverySummary> deliveries;

  const _ResponsiveDeliveryGrid({required this.deliveries});

  static const _spacing = 12.0;
  static const _maxTileWidth = 420.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // 1 column under ~700px (phones), growing by one column per
        // extra ~420px of width beyond that, capped so tiles never
        // stretch absurdly thin on ultra-wide screens.
        final columns = width < 700
            ? 1
            : (width / _maxTileWidth).floor().clamp(1, 4);
        final tileWidth = columns == 1
            ? width
            : (width - _spacing * (columns - 1)) / columns;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Wrap(
            spacing: _spacing,
            runSpacing: _spacing,
            children: [
              for (final delivery in deliveries)
                SizedBox(
                  width: tileWidth,
                  child: _DeliveryTile(delivery: delivery),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _DeliveryTile extends StatelessWidget {
  final DeliverySummary delivery;

  const _DeliveryTile({required this.delivery});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final order = delivery.order;

    final cropLabel = order.cropNames.isNotEmpty
        ? order.cropNames.join(', ')
        : 'Order';

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              OrderDetailScreen(orderId: order.id, viewerRole: 'driver'),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  order.displayId,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                OrderStatusChip(status: order.status),
              ],
            ),
            const SizedBox(height: 12),

            // Pickup to dropoff visual
            Row(
              children: [
                // Dots and line
                Column(
                  children: [
                    Icon(
                      Icons.storefront,
                      size: 14,
                      color: theme.colorScheme.primary,
                    ),
                    Container(
                      width: 2,
                      height: 16,
                      color: theme.colorScheme.outlineVariant,
                    ),
                    Icon(
                      Icons.location_on,
                      size: 14,
                      color: theme.colorScheme.error,
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        delivery.farmerDisplayName ?? 'Farmer',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        delivery.buyerDisplayName ?? 'Buyer',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),
            Divider(color: theme.colorScheme.outlineVariant),
            const SizedBox(height: 6),

            Row(
              children: [
                if (order.firstImageUrl != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: MediaImage(
                        path: order.firstImageUrl!,
                        bucket: 'crop-photos',
                        placeholder: Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: Icon(
                            Icons.image_outlined,
                            size: 12,
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ] else ...[
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    cropLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

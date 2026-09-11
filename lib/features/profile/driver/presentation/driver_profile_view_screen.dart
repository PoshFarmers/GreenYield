import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/auth/auth_providers.dart';
import '../../../../core/theme/theme_provider.dart';
import '../../../../core/widgets/avatar_image.dart';
import '../../../../features/navigation/presentation/app_nav_shell.dart';
import '../../../../models/driver_profile.dart';
import '../../../../models/profile.dart';
import '../../../../models/wallet.dart';
import '../../../wallet/wallet_service.dart';
import '../driver_profile_service.dart';
import 'driver_manage_routes_screen.dart';
import 'driver_profile_edit_screen.dart';
import 'widgets/route_draft_editor.dart'; // weekdayKeys, RouteDayPill

/// Driver's profile screen — mirrors the Figma "Profile" design.
///
/// Data notes:
/// * Name, phone, avatar, and vehicle come straight from PowerSync
///   ([Profile] / [DriverProfile]), same as before.
/// * Preferred routes are now real, backed by `driver_route_preference`
///   via [DriverProfileService.watchRoutes] — see [_PreferredRoutesSection].
/// * Rating, completion %, lifetime earnings, wallet balance, and
///   bank/payout details still aren't modelled anywhere in the schema
///   (no `rating`, `wallet`, or `payout` tables/columns exist as of this
///   branch). Those sections render clearly marked placeholder data
///   below so the screen matches the Figma pixel-for-pixel; swap
///   `_DriverStats.placeholder()` etc. for real providers once that
///   backend work lands.
class DriverProfileViewScreen extends ConsumerStatefulWidget {
  final Profile? initialProfile;

  const DriverProfileViewScreen({super.key, this.initialProfile});

  @override
  ConsumerState<DriverProfileViewScreen> createState() =>
      _DriverProfileViewScreenState();
}

class _DriverProfileViewScreenState
    extends ConsumerState<DriverProfileViewScreen> {
  final _service = DriverProfileService();

  late final Stream<Profile?> _profileStream;
  late final Stream<DriverProfile?> _driverProfileStream;

  bool _pushNotificationsEnabled = true;
  bool _prefsLoaded = false;

  static const _notifPrefsKey = 'push_notifications_enabled';

  @override
  void initState() {
    super.initState();
    final userId = ref.read(authServiceProvider).currentUser!.id;
    _profileStream = ref.read(authServiceProvider).watchOwnProfile();
    _driverProfileStream = _service.watchOwnProfile(userId);
    _loadNotificationPref();
  }

  Future<void> _loadNotificationPref() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _pushNotificationsEnabled = prefs.getBool(_notifPrefsKey) ?? true;
      _prefsLoaded = true;
    });
  }

  Future<void> _setNotificationPref(bool value) async {
    setState(() => _pushNotificationsEnabled = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notifPrefsKey, value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _ProfileAppBar(),
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
            return Center(child: Text('profile_not_found'.tr()));
          }

          return StreamBuilder<DriverProfile?>(
            stream: _driverProfileStream,
            builder: (context, driverSnapshot) {
              if (!driverSnapshot.hasData && !driverSnapshot.hasError) {
                return const Center(child: CircularProgressIndicator());
              }
              if (driverSnapshot.hasError) {
                return Center(child: Text(driverSnapshot.error.toString()));
              }

              final driverProfile = driverSnapshot.data;
              if (driverProfile == null) {
                return Center(child: Text('driver_profile_not_found'.tr()));
              }

              return _ProfileBody(
                profile: profile,
                driverProfile: driverProfile,
                pushNotificationsEnabled: _pushNotificationsEnabled,
                notifPrefReady: _prefsLoaded,
                onPushNotificationsChanged: _setNotificationPref,
                onEditVehicle: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DriverProfileEditScreen(
                        genericProfile: profile,
                        profile: driverProfile,
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
      bottomNavigationBar: const _DriverBottomNav(),
    );
  }
}

/// Back arrow + centered "Profile" title + help icon, matching the
/// plain-AppBar convention this app already uses for screens with a
/// dedicated title (see `AppHeader` doc comment) — restyled to match
/// the Figma header exactly.
class _ProfileAppBar extends StatelessWidget implements PreferredSizeWidget {
  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      centerTitle: true,
      leading: BackButton(onPressed: () => Navigator.of(context).maybePop()),
      title: Text(
        'profile_title'.tr(),
        style: Theme.of(context).textTheme.titleLarge,
      ),
      actions: [
        IconButton(
          tooltip: 'help'.tr(),
          icon: const Icon(Icons.help_outline),
          onPressed: () {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: Text('help'.tr()),
                content: Text('profile_help_body'.tr()),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('ok'.tr()),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _ProfileBody extends ConsumerWidget {
  final Profile profile;
  final DriverProfile driverProfile;
  final bool pushNotificationsEnabled;
  final bool notifPrefReady;
  final ValueChanged<bool> onPushNotificationsChanged;
  final VoidCallback onEditVehicle;

  const _ProfileBody({
    required this.profile,
    required this.driverProfile,
    required this.pushNotificationsEnabled,
    required this.notifPrefReady,
    required this.onPushNotificationsChanged,
    required this.onEditVehicle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicle = driverProfile.primaryVehicle;
    final width = MediaQuery.sizeOf(context).width;
    // Comfortable reading width on tablets/desktop; fills the screen
    // (minus gutters) on phones.
    final maxWidth = width < 480 ? width : 480.0;
    final hPad = width < 360 ? 16.0 : 20.0;

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: ListView(
            padding: EdgeInsets.fromLTRB(hPad, 20, hPad, 32),
            children: [
              _AvatarHeader(profile: profile),
              const SizedBox(height: 20),
              const _StatsCard(),
              const SizedBox(height: 16),
              _WalletCard(profileId: driverProfile.profileId),
              const SizedBox(height: 24),
              _VehiclesSection(vehicle: vehicle, onEdit: onEditVehicle),
              const SizedBox(height: 24),
              _PreferredRoutesSection(
                driverProfileId: driverProfile.profileId,
                routes: driverProfile.routePreferences,
              ),
              const SizedBox(height: 24),
              const _FinancialDetailsSection(),
              const SizedBox(height: 24),
              _SettingsSection(
                pushNotificationsEnabled: pushNotificationsEnabled,
                notifPrefReady: notifPrefReady,
                onPushNotificationsChanged: onPushNotificationsChanged,
              ),
              const SizedBox(height: 24),
              Center(
                child: TextButton(
                  onPressed: () => _confirmLogOut(context, ref),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.onSurface,
                  ),
                  child: Text('logout'.tr()),
                ),
              ),
              Center(
                child: TextButton(
                  onPressed: () => _confirmDeleteAccount(context),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  child: Text('delete_account'.tr()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmLogOut(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('logout'.tr()),
        content: Text('logout_confirm_body'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('cancel'.tr()),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await ref.read(authServiceProvider).signOut();
            },
            child: Text('logout'.tr()),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteAccount(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('delete_account'.tr()),
        content: Text('delete_account_confirm_body'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('cancel'.tr()),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              // TODO: wire up once account deletion exists server-side
              // (no `delete_own_account` RPC / endpoint yet).
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('delete_account_not_available'.tr())),
              );
            },
            child: Text('delete'.tr()),
          ),
        ],
      ),
    );
  }
}

// --- Avatar / name header -------------------------------------------------

class _AvatarHeader extends StatelessWidget {
  final Profile profile;

  const _AvatarHeader({required this.profile});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            AvatarImage(path: profile.avatarUrl, radius: 52),
            Positioned(right: -2, bottom: -2, child: _EditBadge(onTap: () {})),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          children: [
            Text(
              '${profile.firstName} ${profile.lastName}',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Icon(Icons.verified, color: theme.colorScheme.primary, size: 20),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          profile.phone ?? '-',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            'verified_driver'.tr(),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _EditBadge extends StatelessWidget {
  final VoidCallback onTap;

  const _EditBadge({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      shape: CircleBorder(side: BorderSide(color: theme.colorScheme.outline)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(Icons.edit, size: 14, color: theme.colorScheme.primary),
        ),
      ),
    );
  }
}

// --- Stats card -------------------------------------------------------

class _StatsCard extends StatelessWidget {
  const _StatsCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Placeholder — no ratings/completion/earnings backend yet.
    return _CardShell(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Row(
        children: [
          Expanded(
            child: _StatItem(
              value: '4.9',
              icon: Icons.star_rounded,
              iconColor: const Color(0xFFF5A623),
              label: 'rating'.tr(),
            ),
          ),
          _StatDivider(),
          Expanded(
            child: _StatItem(value: '98.5%', label: 'completion'.tr()),
          ),
          _StatDivider(),
          Expanded(
            child: _StatItem(
              value: '185k',
              label: 'earned_rs'.tr(),
              valueColor: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 36,
      color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String value;
  final String label;
  final IconData? icon;
  final Color? iconColor;
  final Color? valueColor;

  const _StatItem({
    required this.value,
    required this.label,
    this.icon,
    this.iconColor,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 2),
            ],
            Flexible(
              child: Text(
                value,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: valueColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}

// --- Wallet card --------------------------------------------------------

class _WalletCard extends StatelessWidget {
  final String profileId;

  const _WalletCard({required this.profileId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _CardShell(
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.account_balance_wallet_outlined,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'wallet_balance'.tr(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                StreamBuilder<Wallet?>(
                  stream: const WalletService().watchBalance(profileId),
                  builder: (context, snapshot) {
                    final wallet = snapshot.data;
                    final text = wallet == null
                        ? '${'LKR'} 0.00'
                        : '${wallet.currency} ${wallet.balance.toStringAsFixed(2)}';
                    return Text(
                      text,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          TextButton(onPressed: () {}, child: Text('view'.tr())),
        ],
      ),
    );
  }
}

// --- Vehicles -------------------------------------------------------------

class _VehiclesSection extends StatelessWidget {
  final Vehicle? vehicle;
  final VoidCallback onEdit;

  const _VehiclesSection({required this.vehicle, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          title: 'vehicles'.tr(),
          action: TextButton.icon(
            onPressed: onEdit,
            icon: const Icon(Icons.add, size: 18),
            label: Text('add_vehicle'.tr()),
          ),
        ),
        if (vehicle == null)
          _CardShell(child: Text('no_vehicle_added'.tr()))
        else
          _VehicleCard(vehicle: vehicle!, onEdit: onEdit),
        const SizedBox(height: 12),
        InkWell(
          onTap: onEdit,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 22),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.colorScheme.outline,
                strokeAlign: BorderSide.strokeAlignInside,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.local_shipping_outlined,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 6),
                Text(
                  'add_secondary_vehicle'.tr(),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _VehicleCard extends StatelessWidget {
  final Vehicle vehicle;
  final VoidCallback onEdit;

  const _VehicleCard({required this.vehicle, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _CardShell(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                  // No vehicle-photo field on the model yet — a
                  // themed placeholder stands in for the Figma photo.
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          theme.colorScheme.primary.withValues(alpha: 0.55),
                          theme.colorScheme.primary.withValues(alpha: 0.85),
                        ],
                      ),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.local_shipping,
                        color: Colors.white,
                        size: 48,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 12,
                  bottom: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'primary'.tr().toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onPrimary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 10,
                  top: 10,
                  child: _EditBadge(onTap: onEdit),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'vehicle_type_${vehicle.vehicleType}'.tr(),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondary,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        vehicle.plateNumber,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${'vehicle_capacity'.tr()}: ${vehicle.capacity}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- Preferred routes -------------------------------------------------

class _PreferredRoutesSection extends StatelessWidget {
  final String driverProfileId;
  final List<RoutePreference> routes;

  const _PreferredRoutesSection({
    required this.driverProfileId,
    required this.routes,
  });

  void _openManageRoutes(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            DriverManageRoutesScreen(driverProfileId: driverProfileId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeRoutes = routes.where((r) => r.isActive).toList();
    final displayRoute = activeRoutes.isNotEmpty
        ? activeRoutes.first
        : (routes.isNotEmpty ? routes.first : null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          title: 'preferred_routes'.tr(),
          action: IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: () => _openManageRoutes(context),
          ),
        ),
        if (displayRoute == null)
          _CardShell(
            child: InkWell(
              onTap: () => _openManageRoutes(context),
              child: Row(
                children: [
                  Icon(Icons.add_road, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(child: Text('no_routes_added'.tr())),
                  Icon(
                    Icons.chevron_right,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                ],
              ),
            ),
          )
        else
          _CardShell(
            child: InkWell(
              onTap: () => _openManageRoutes(context),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'route'.tr().toUpperCase(),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.55,
                            ),
                            letterSpacing: 0.6,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                displayRoute.originLocation,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Icon(
                              Icons.sync_alt,
                              size: 18,
                              color: theme.colorScheme.primary,
                            ),
                            Flexible(
                              child: Text(
                                displayRoute.destinationLocation,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (displayRoute.activeDayKeys.isNotEmpty)
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final day in weekdayKeys)
                                if (displayRoute.activeDayKeys.contains(day))
                                  RouteDayPill(dayKey: day),
                            ],
                          ),
                        if (routes.length > 1) ...[
                          const SizedBox(height: 8),
                          Text(
                            'plus_n_more_routes'.tr(
                              namedArgs: {'count': '${routes.length - 1}'},
                            ),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.14,
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.sync_alt,
                          color: theme.colorScheme.primary,
                          size: 18,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _directionKey(displayRoute.direction).tr(),
                        textAlign: TextAlign.right,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  String _directionKey(RouteDirection direction) {
    switch (direction) {
      case RouteDirection.outbound:
        return 'outbound';
      case RouteDirection.returnTrip:
        return 'return_trip';
      case RouteDirection.both:
        return 'outbound_and_return';
    }
  }
}

// --- Financial details ------------------------------------------------

class _FinancialDetailsSection extends StatelessWidget {
  const _FinancialDetailsSection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Placeholder — no bank-account/payout provider yet (`payment_and_
    // refund` tables exist in Supabase, no Dart service on top of them).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(title: 'financial_details'.tr()),
        _CardShell(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.account_balance_outlined,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Commercial Bank',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '**** **** **** 4589',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'recent_payout'.tr(),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.6,
                              ),
                            ),
                          ),
                          Text(
                            'Rs. 45,000',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'processing'.tr().toUpperCase(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: TextButton(
                  onPressed: () {},
                  child: Text('view_full_payment_history'.tr()),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// --- Settings -----------------------------------------------------------

class _SettingsSection extends ConsumerWidget {
  final bool pushNotificationsEnabled;
  final bool notifPrefReady;
  final ValueChanged<bool> onPushNotificationsChanged;

  const _SettingsSection({
    required this.pushNotificationsEnabled,
    required this.notifPrefReady,
    required this.onPushNotificationsChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final themeMode = ref.watch(themeModeProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(title: 'settings'.tr()),
        _CardShell(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _SettingsRow(
                icon: Icons.language,
                label: 'language'.tr(),
                value: context.locale.languageCode.toUpperCase(),
                onTap: () => _showLanguageSheet(context),
              ),
              Divider(height: 1, color: theme.colorScheme.outline),
              _SettingsRow(
                icon: Icons.palette_outlined,
                label: 'app_theme'.tr(),
                value: _themeModeLabel(themeMode),
                onTap: () => _showThemeSheet(context, ref, themeMode),
              ),
              Divider(height: 1, color: theme.colorScheme.outline),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.notifications_none,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'push_notifications'.tr(),
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                    Switch(
                      value: pushNotificationsEnabled,
                      onChanged: notifPrefReady
                          ? onPushNotificationsChanged
                          : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _themeModeLabel(ThemeMode mode) => switch (mode) {
    ThemeMode.light => 'theme_light'.tr(),
    ThemeMode.dark => 'theme_dark'.tr(),
    ThemeMode.system => 'theme_system'.tr(),
  };

  void _showLanguageSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'language'.tr(),
                    style: Theme.of(sheetContext).textTheme.titleMedium,
                  ),
                ),
              ),
              for (final locale in sheetContext.supportedLocales)
                RadioListTile<Locale>(
                  value: locale,
                  groupValue: sheetContext.locale,
                  title: Text(_languageLabel(locale.languageCode)),
                  onChanged: (value) {
                    if (value != null) sheetContext.setLocale(value);
                    Navigator.of(sheetContext).pop();
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  String _languageLabel(String code) => switch (code) {
    'en' => 'English',
    'si' => 'සිංහල',
    'ta' => 'தமிழ்',
    _ => code.toUpperCase(),
  };

  void _showThemeSheet(BuildContext context, WidgetRef ref, ThemeMode current) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'app_theme'.tr(),
                    style: Theme.of(sheetContext).textTheme.titleMedium,
                  ),
                ),
              ),
              RadioListTile<ThemeMode>(
                value: ThemeMode.light,
                groupValue: current,
                secondary: const Icon(Icons.light_mode_outlined),
                title: Text('theme_light'.tr()),
                onChanged: (value) {
                  ref.read(themeModeProvider.notifier).setThemeMode(value!);
                  Navigator.of(sheetContext).pop();
                },
              ),
              RadioListTile<ThemeMode>(
                value: ThemeMode.dark,
                groupValue: current,
                secondary: const Icon(Icons.dark_mode_outlined),
                title: Text('theme_dark'.tr()),
                onChanged: (value) {
                  ref.read(themeModeProvider.notifier).setThemeMode(value!);
                  Navigator.of(sheetContext).pop();
                },
              ),
              RadioListTile<ThemeMode>(
                value: ThemeMode.system,
                groupValue: current,
                secondary: const Icon(Icons.settings_suggest_outlined),
                title: Text('theme_system'.tr()),
                onChanged: (value) {
                  ref.read(themeModeProvider.notifier).setThemeMode(value!);
                  Navigator.of(sheetContext).pop();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  const _SettingsRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(
              icon,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 14),
            Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
            Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Shared bits ----------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  final String title;
  final Widget? action;

  const _SectionHeader({required this.title, this.action});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

class _CardShell extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _CardShell({
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 0),
      padding: padding,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: child,
    );
  }
}

/// A bottom nav bar matching the driver tabs registered in
/// `role_nav_shell_registry.dart` (Home / Calendar / Deliveries / Chat).
/// This screen is pushed with `Navigator.push` on top of `AppNavShell`
/// (same as every other profile/edit screen in the app), so Flutter
/// doesn't render the shell's own bottom bar here — this mirrors it so
/// the chrome matches the Figma, and jumps back into the right tab.
class _DriverBottomNav extends ConsumerWidget {
  const _DriverBottomNav();

  static const _tabs = [
    (icon: Icons.home_outlined, label: 'Home'),
    (icon: Icons.calendar_today_outlined, label: 'Calendar'),
    (icon: Icons.local_shipping_outlined, label: 'Deliveries'),
    (icon: Icons.chat_bubble_outline, label: 'Chat'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return NavigationBar(
      selectedIndex: 0,
      destinations: [
        for (final tab in _tabs)
          NavigationDestination(icon: Icon(tab.icon), label: tab.label),
      ],
      onDestinationSelected: (index) {
        ref.read(navShellIndexProvider.notifier).select(index);
        Navigator.of(context).popUntil((route) => route.isFirst);
      },
    );
  }
}

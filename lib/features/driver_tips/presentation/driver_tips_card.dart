import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/driver_stop.dart';
import '../driver_tip_rules.dart';
import '../driver_tips_models.dart';
import '../driver_tips_service.dart';

/// "Today's tips" on the driver home: a forecast strip for the working day
/// plus a few practical, cargo-aware tips. Self-contained — it only reads
/// the stops it's given, so the map/shift/GPS logic around it is untouched.
class DriverTipsCard extends ConsumerStatefulWidget {
  final List<DriverStop> stops;

  const DriverTipsCard({super.key, required this.stops});

  @override
  ConsumerState<DriverTipsCard> createState() => _DriverTipsCardState();
}

class _DriverTipsCardState extends ConsumerState<DriverTipsCard> {
  static const _collapsedCount = 2;
  final _dismissedStore = const DismissedTipsStore();

  Future<DriverTipsResult>? _future;
  String? _signature;
  Set<String> _dismissed = {};
  bool _expanded = false;

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void initState() {
    super.initState();
    _dismissedStore.load(_today).then((ids) {
      if (mounted) setState(() => _dismissed = ids);
    });
  }

  /// Recompute only when something the tips depend on changes: pending
  /// stops and their crops, the demo settings, or the language.
  void _refreshIfNeeded(DriverTipsDemoState demo, String languageCode) {
    final stopsSig = widget.stops
        .map((s) => '${s.deliveryId}:${s.type.name}:${s.isDone}:${s.cropNames}')
        .join('|');
    final signature =
        '$stopsSig#${demo.scenario?.name}#${demo.sampleCargo}#$languageCode';
    if (signature == _signature) return;
    _signature = signature;
    _future = ref
        .read(driverTipsServiceProvider)
        .tipsFor(
          day: _today,
          stops: widget.stops,
          languageCode: languageCode,
          scenario: demo.scenario,
          sampleCargoWhenEmpty: demo.sampleCargo,
        );
  }

  Future<void> _dismiss(String id) async {
    setState(() => _dismissed = {..._dismissed, id});
    await _dismissedStore.save(_today, _dismissed);
  }

  Future<void> _restoreAll() async {
    setState(() => _dismissed = {});
    await _dismissedStore.save(_today, const {});
  }

  @override
  Widget build(BuildContext context) {
    final demo = ref.watch(driverTipsDemoProvider);
    _refreshIfNeeded(demo, context.locale.languageCode);
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
      child: FutureBuilder<DriverTipsResult>(
        future: _future,
        builder: (context, snapshot) {
          final result = snapshot.data;
          return AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: snapshot.hasError
                ? _buildMessage(
                    theme,
                    Icons.cloud_off_outlined,
                    'tips_unavailable'.tr(),
                  )
                : result == null
                ? _buildLoading(theme)
                : _buildResult(theme, result),
          );
        },
      ),
    );
  }

  Widget _buildResult(ThemeData theme, DriverTipsResult result) {
    final visible = result.tips
        .where((t) => !_dismissed.contains(t.id))
        .toList();
    final shown = _expanded ? visible : visible.take(_collapsedCount).toList();
    final hidden = visible.length - shown.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          result: result,
          headline: result.tips.isEmpty ? null : result.tips.first.title,
          onDemo: result.weather.isSample ? _openDemoSheet : null,
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: _WeatherStrip(weather: result.weather),
        ),
        const SizedBox(height: 12),
        if (result.cargo.isEmpty)
          _buildMessage(
            theme,
            Icons.local_shipping_outlined,
            'tips_no_stops'.tr(),
          )
        else if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text('tips_all_done'.tr())),
                TextButton(
                  onPressed: _restoreAll,
                  child: Text('tips_show_again'.tr()),
                ),
              ],
            ),
          )
        else ...[
          for (final tip in shown)
            Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 8),
              child: _TipTile(tip: tip, onDismiss: () => _dismiss(tip.id)),
            ),
          if (hidden > 0 || _expanded && visible.length > _collapsedCount)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                label: Text(
                  _expanded
                      ? 'tips_show_less'.tr()
                      : 'tips_show_more'.tr(namedArgs: {'count': '$hidden'}),
                ),
              ),
            ),
        ],
        if (result.cargo.isSample)
          Padding(
            padding: const EdgeInsets.only(top: 4, right: 8),
            child: Text(
              'tips_sample_cargo_note'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 4, right: 8),
          child: Text(
            'tips_disclaimer'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoading(ThemeData theme) {
    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              bar(40, 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'tips_loading'.tr(),
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    bar(140, 10),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          bar(double.infinity, 56),
          const SizedBox(height: 10),
          bar(double.infinity, 48),
        ],
      ),
    );
  }

  Widget _buildMessage(ThemeData theme, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 4),
      child: Row(
        children: [
          Icon(icon, color: theme.colorScheme.outline),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }

  Future<void> _openDemoSheet() {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => const _DemoSheet(),
    );
  }
}

/// Weather icon + "Today's tips" + the headline tip, with the sample badge
/// and (sample forecast only) the demo button.
class _Header extends StatelessWidget {
  final DriverTipsResult result;
  final String? headline;
  final VoidCallback? onDemo;

  const _Header({required this.result, this.headline, this.onDemo});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color) = _scenarioVisual(result.scenario, theme);

    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Wrap, not Row: in si/ta the title + badge don't fit side by
              // side on a phone, so the badge drops to its own line.
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'tips_title'.tr(),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (result.weather.isSample)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'tips_sample_badge'.tr(),
                        style: theme.textTheme.labelSmall,
                      ),
                    ),
                ],
              ),
              if (headline != null)
                Text(
                  headline!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: color),
                ),
            ],
          ),
        ),
        if (onDemo != null)
          IconButton(
            tooltip: 'tips_demo_title'.tr(),
            onPressed: onDemo,
            icon: const Icon(Icons.tune),
          ),
      ],
    );
  }
}

(IconData, Color) _scenarioVisual(WeatherScenario s, ThemeData theme) =>
    switch (s) {
      WeatherScenario.rainyAfternoon => (
        Icons.thunderstorm_outlined,
        const Color(0xFF1E88E5),
      ),
      WeatherScenario.hotDry => (
        Icons.wb_sunny_outlined,
        const Color(0xFFEF6C00),
      ),
      WeatherScenario.windy => (Icons.air, const Color(0xFF00897B)),
      WeatherScenario.clearMild => (
        Icons.wb_cloudy_outlined,
        theme.colorScheme.primary,
      ),
    };

/// Every-2-hours strip across the working day: time, icon, rain chance,
/// temperature. Rainy slots are tinted so the "rain window" reads at a
/// glance.
class _WeatherStrip extends StatelessWidget {
  final WeatherSummary weather;

  const _WeatherStrip({required this.weather});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locale = context.locale.toString();
    final now = DateTime.now();
    final slots = weather.hours.where((h) => h.hour % 2 == 0).toList();
    const rainBlue = Color(0xFF1E88E5);

    return Row(
      children: [
        for (final h in slots)
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: h.rainProbability >= rainThreshold
                    ? rainBlue.withValues(alpha: 0.12)
                    : theme.colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.5,
                      ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  FittedBox(
                    child: Text(
                      DateFormat.j(
                        locale,
                      ).format(DateTime(now.year, now.month, now.day, h.hour)),
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Icon(
                    h.rainProbability >= rainThreshold
                        ? Icons.water_drop
                        : h.temperatureC >= heatThresholdC
                        ? Icons.wb_sunny
                        : h.windKmh >= windThresholdKmh
                        ? Icons.air
                        : h.rainProbability >= 30
                        ? Icons.cloud_outlined
                        : Icons.wb_sunny_outlined,
                    size: 18,
                    color: h.rainProbability >= rainThreshold
                        ? rainBlue
                        : h.temperatureC >= heatThresholdC
                        ? const Color(0xFFEF6C00)
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    child: Text(
                      '${h.rainProbability}%',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: h.rainProbability >= rainThreshold
                            ? rainBlue
                            : theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  FittedBox(
                    child: Text(
                      '${h.temperatureC.round()}°',
                      style: theme.textTheme.labelSmall,
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

class _TipTile extends StatefulWidget {
  final DriverTip tip;
  final VoidCallback onDismiss;

  const _TipTile({required this.tip, required this.onDismiss});

  @override
  State<_TipTile> createState() => _TipTileState();
}

class _TipTileState extends State<_TipTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tip = widget.tip;
    final (icon, color) = switch (tip.severity) {
      TipSeverity.warning => (
        Icons.warning_amber_rounded,
        theme.colorScheme.error,
      ),
      TipSeverity.caution => (Icons.error_outline, AppColors.warnAmber),
      TipSeverity.info => (Icons.lightbulb_outline, theme.colorScheme.primary),
    };

    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _open = !_open),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border(left: BorderSide(color: color, width: 4)),
          ),
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 20, color: color),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tip.title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          tip.body,
                          maxLines: _open ? null : 2,
                          overflow: _open ? null : TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _open ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: theme.colorScheme.outline,
                  ),
                ],
              ),
              if (_open) ...[
                if (tip.relatedCrops.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 30),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final crop in tip.relatedCrops)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surface,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: theme.colorScheme.outlineVariant,
                              ),
                            ),
                            child: Text(
                              crop,
                              style: theme.textTheme.labelSmall,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: widget.onDismiss,
                    icon: const Icon(Icons.check, size: 18),
                    label: Text('tips_got_it'.tr()),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Presenter controls: pick the weather the sample tips are based on, and
/// optionally use sample cargo when the demo account has no stops.
class _DemoSheet extends ConsumerWidget {
  const _DemoSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final demo = ref.watch(driverTipsDemoProvider);
    final notifier = ref.read(driverTipsDemoProvider.notifier);

    Widget option(WeatherScenario? scenario, IconData icon, String label) {
      final selected = demo.scenario == scenario;
      return ListTile(
        leading: Icon(icon),
        title: Text(label),
        trailing: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_off,
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.outline,
        ),
        onTap: () => notifier.setScenario(scenario),
      );
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(
                'tips_demo_title'.tr(),
                style: theme.textTheme.titleLarge,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'tips_demo_hint'.tr(),
                style: theme.textTheme.bodySmall,
              ),
            ),
            option(null, Icons.autorenew, 'tips_demo_auto'.tr()),
            option(
              WeatherScenario.rainyAfternoon,
              Icons.thunderstorm_outlined,
              'weather_rainy'.tr(),
            ),
            option(
              WeatherScenario.hotDry,
              Icons.wb_sunny_outlined,
              'weather_hot'.tr(),
            ),
            option(WeatherScenario.windy, Icons.air, 'weather_windy'.tr()),
            option(
              WeatherScenario.clearMild,
              Icons.wb_cloudy_outlined,
              'weather_clear'.tr(),
            ),
            const Divider(),
            SwitchListTile(
              value: demo.sampleCargo,
              onChanged: notifier.setSampleCargo,
              title: Text('tips_demo_sample_cargo'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}

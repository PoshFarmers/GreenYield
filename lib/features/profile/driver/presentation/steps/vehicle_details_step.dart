import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../../core/widgets/app_text_field.dart';

/// One selectable "Vehicle Category" card, matching the icon + label +
/// seat-count subtitle used on the Vehicle Details screen.
class VehicleCategoryOption {
  final String type;
  final IconData icon;

  const VehicleCategoryOption({required this.type, required this.icon});
}

/// Categories shown as cards on the Vehicle Details step. Keyed to the
/// existing `vehicle_type` enum values (three_wheeler/van/lorry/truck/
/// tractor) so no schema change is needed — only the presentation is
/// redesigned into cards. Add/remove entries here to change what's
/// offered without touching layout code.
const vehicleCategoryOptions = [
  VehicleCategoryOption(type: 'three_wheeler', icon: Icons.moped),
  VehicleCategoryOption(type: 'van', icon: Icons.airport_shuttle),
  VehicleCategoryOption(type: 'lorry', icon: Icons.local_shipping),
  VehicleCategoryOption(type: 'truck', icon: Icons.fire_truck),
  VehicleCategoryOption(type: 'tractor', icon: Icons.agriculture),
];

/// Step 1 of driver registration — vehicle category, plate number, and
/// the two capacity fields, laid out as clean input cards per the
/// "Vehicle Details" design. Purely presentational: all state lives in
/// the parent flow so Step 2 can read it back on final submit.
class VehicleDetailsStep extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final String selectedType;
  final ValueChanged<String> onTypeChanged;
  final TextEditingController makeModelController;
  final TextEditingController plateNumberController;
  final TextEditingController capacityController;
  final TextEditingController preferredCapacityController;

  const VehicleDetailsStep({
    super.key,
    required this.formKey,
    required this.selectedType,
    required this.onTypeChanged,
    required this.makeModelController,
    required this.plateNumberController,
    required this.capacityController,
    required this.preferredCapacityController,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _IntroCard(
              icon: Icons.local_taxi_outlined,
              title: 'vehicle_registration'.tr(),
              body: 'vehicle_registration_hint'.tr(),
            ),
            const SizedBox(height: 24),
            Text(
              'select_vehicle_category'.tr(),
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 10),
            _CategoryCardRow(
              selectedType: selectedType,
              onChanged: onTypeChanged,
            ),
            const SizedBox(height: 20),
            RegistrationFormCard(
              children: [
                AppTextField(
                  label: 'vehicle_make_model'.tr(),
                  controller: makeModelController,
                  semanticsHint: 'vehicle_make_model_example'.tr(),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'error_required'.tr()
                      : null,
                ),
                const SizedBox(height: 16),
                AppTextField(
                  label: 'plate_number'.tr(),
                  controller: plateNumberController,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'error_required'.tr()
                      : null,
                ),
                const SizedBox(height: 16),
                // Capacity + preferred capacity side by side on wide
                // screens, stacked on narrow ones (small-phone layout).
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 340;
                    final capacityField = AppTextField(
                      label: 'vehicle_capacity'.tr(),
                      controller: capacityController,
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        final parsed = int.tryParse((v ?? '').trim());
                        if (parsed == null) return 'error_required'.tr();
                        if (parsed <= 0) {
                          return 'error_capacity_positive'.tr();
                        }
                        return null;
                      },
                    );
                    final preferredField = AppTextField(
                      label: 'preferred_capacity'.tr(),
                      controller: preferredCapacityController,
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        final text = (v ?? '').trim();
                        if (text.isEmpty) return null;
                        final parsed = int.tryParse(text);
                        final capacity = int.tryParse(
                          capacityController.text.trim(),
                        );
                        if (parsed == null) return 'error_required'.tr();
                        if (capacity != null && parsed > capacity) {
                          return 'error_preferred_capacity_exceeds'.tr();
                        }
                        return null;
                      },
                    );
                    if (isNarrow) {
                      return Column(
                        children: [
                          capacityField,
                          const SizedBox(height: 16),
                          preferredField,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: capacityField),
                        const SizedBox(width: 16),
                        Expanded(child: preferredField),
                      ],
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            _NoticeCard(text: 'vehicle_verification_notice'.tr()),
          ],
        ),
      ),
    );
  }
}

class _CategoryCardRow extends StatelessWidget {
  final String selectedType;
  final ValueChanged<String> onChanged;

  const _CategoryCardRow({required this.selectedType, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Wrap instead of a fixed Row so extra categories (or a tablet's
        // wider constraints) reflow instead of overflowing.
        final cardWidth = (constraints.maxWidth - 16) / 3;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in vehicleCategoryOptions)
              SizedBox(
                width: cardWidth.clamp(96.0, 160.0),
                child: _CategoryCard(
                  option: option,
                  selected: option.type == selectedType,
                  onTap: () => onChanged(option.type),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final VehicleCategoryOption option;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.outlineVariant;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.08)
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: selected ? 1.6 : 1),
        ),
        child: Stack(
          children: [
            if (selected)
              Positioned(
                top: -2,
                right: -2,
                child: Icon(
                  Icons.check_circle,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
              ),
            Column(
              children: [
                Icon(
                  option.icon,
                  size: 26,
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
                const SizedBox(height: 8),
                Text(
                  'vehicle_type_${option.type}'.tr(),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'vehicle_type_${option.type}_hint'.tr(),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
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

class _IntroCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _IntroCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RegistrationFormCard(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: theme.colorScheme.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _NoticeCard extends StatelessWidget {
  final String text;

  const _NoticeCard({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.shield_outlined,
            size: 18,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared "clean modern input card" shell used across both steps.
class RegistrationFormCard extends StatelessWidget {
  final List<Widget> children;

  const RegistrationFormCard({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

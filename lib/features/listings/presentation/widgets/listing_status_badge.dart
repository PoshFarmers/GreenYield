import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Coloured pill for a listing's status ('active' | 'sold_out' |
/// 'expired' | 'flagged'), shared by the Harvest tab's cards and the
/// edit-listing screen.
class ListingStatusBadge extends StatelessWidget {
  final String status;

  const ListingStatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (color, labelKey) = switch (status) {
      'active' => (theme.colorScheme.primary, 'status_active'),
      'sold_out' => (theme.colorScheme.error, 'status_sold_out'),
      'expired' => (theme.colorScheme.outline, 'status_expired'),
      _ => (theme.colorScheme.tertiary, 'status_flagged'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        labelKey.tr(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../models/linked_card.dart';

/// Compact brand badge. Text-based so it needs no image assets.
class CardBrandIcon extends StatelessWidget {
  final CardBrand brand;
  final double width;

  const CardBrandIcon({super.key, required this.brand, this.width = 44});

  String get _label => switch (brand) {
    CardBrand.visa => 'VISA',
    CardBrand.mastercard => 'MC',
    CardBrand.amex => 'AMEX',
    CardBrand.discover => 'DISC',
    CardBrand.other => '',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: width,
      height: width * 0.66,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: brand == CardBrand.other
          ? Icon(
              Icons.credit_card,
              size: width * 0.5,
              color: theme.colorScheme.primary,
            )
          : Text(
              _label,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: width * 0.26,
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.primary,
              ),
            ),
    );
  }
}

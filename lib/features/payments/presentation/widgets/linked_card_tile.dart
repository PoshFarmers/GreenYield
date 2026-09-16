import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../models/linked_card.dart';
import 'card_brand_icon.dart';

enum _CardAction { setDefault, remove }

/// One saved card with a default/expired badge and a set-default / remove menu.
class LinkedCardTile extends StatelessWidget {
  final LinkedCard card;
  final bool enabled;
  final VoidCallback onSetDefault;
  final VoidCallback onRemove;

  const LinkedCardTile({
    super.key,
    required this.card,
    required this.onSetDefault,
    required this.onRemove,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canSetDefault = !card.isDefault && !card.isExpired;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: card.isDefault
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
          width: card.isDefault ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          CardBrandIcon(brand: card.brand),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  card.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  card.nickname == null || card.nickname!.isEmpty
                      ? card.holderName
                      : '${card.maskedNumber}  ·  ${card.holderName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'payments_expires'.tr(namedArgs: {'date': card.expiryLabel}),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: card.isExpired
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (card.isDefault || card.isExpired) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: [
                      if (card.isDefault)
                        _Badge(
                          label: 'payments_default_badge'.tr(),
                          background: theme.colorScheme.primary.withValues(
                            alpha: 0.14,
                          ),
                          foreground: theme.colorScheme.primary,
                        ),
                      if (card.isExpired)
                        _Badge(
                          label: 'payments_expired_badge'.tr(),
                          background: theme.colorScheme.error.withValues(
                            alpha: 0.12,
                          ),
                          foreground: theme.colorScheme.error,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          PopupMenuButton<_CardAction>(
            enabled: enabled,
            onSelected: (action) {
              switch (action) {
                case _CardAction.setDefault:
                  onSetDefault();
                case _CardAction.remove:
                  onRemove();
              }
            },
            itemBuilder: (context) => [
              if (canSetDefault)
                PopupMenuItem(
                  value: _CardAction.setDefault,
                  child: Text('payments_set_default'.tr()),
                ),
              PopupMenuItem(
                value: _CardAction.remove,
                child: Text('payments_remove'.tr()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;

  const _Badge({
    required this.label,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: foreground, fontWeight: FontWeight.w700),
      ),
    );
  }
}

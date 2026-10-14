import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../payments/models/linked_card.dart';
import '../../../payments/payment_gateway.dart';
import '../../../payments/payment_providers.dart';
import '../../../payments/presentation/add_card_sheet.dart';
import '../../../payments/presentation/widgets/card_brand_icon.dart';
import '../../../wallet/presentation/top_up_screen.dart';

// Replaced by the shared money formatter in Task 15.
String _money(num value) => 'LKR ${NumberFormat('#,##0.00').format(value)}';

enum CheckoutPaymentMethod { wallet, card }

/// The card that will be charged: the chosen one if usable, else the default,
/// else the first usable. [extra] is a card added during checkout (one-off
/// cards never appear in `list_linked_cards`).
LinkedCard? resolveCheckoutCard(
  List<LinkedCard>? cards,
  LinkedCard? extra,
  String? chosenId,
) {
  final all = <LinkedCard>[...?cards];
  if (extra != null && !all.any((card) => card.id == extra.id)) all.add(extra);
  final usable = all.where((card) => !card.isExpired).toList();
  for (final card in usable) {
    if (card.id == chosenId) return card;
  }
  for (final card in usable) {
    if (card.isDefault) return card;
  }
  return usable.isEmpty ? null : usable.first;
}

/// Payment selector for checkout: wallet (live balance, low-balance warning
/// with a top-up shortcut) or a card (saved cards plus "add new card").
class CheckoutPaymentSelector extends ConsumerWidget {
  final CheckoutPaymentMethod method;
  final ValueChanged<CheckoutPaymentMethod> onMethodChanged;
  final LinkedCard? selectedCard;
  final LinkedCard? extraCard;
  final ValueChanged<LinkedCard> onCardSelected;
  final ValueChanged<LinkedCard> onCardAdded;
  final double walletBalance;
  final double total;

  const CheckoutPaymentSelector({
    super.key,
    required this.method,
    required this.onMethodChanged,
    required this.selectedCard,
    required this.extraCard,
    required this.onCardSelected,
    required this.onCardAdded,
    required this.walletBalance,
    required this.total,
  });

  Future<void> _addCard(BuildContext context, WidgetRef ref) async {
    final card = await showAddCardSheet(context, showSaveOption: true);
    if (card == null) return;
    ref.invalidate(linkedCardsProvider);
    onCardAdded(card);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cardsAsync = ref.watch(linkedCardsProvider);
    final walletSelected = method == CheckoutPaymentMethod.wallet;
    final walletLow = walletBalance < total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _OptionTile(
          icon: Icons.account_balance_wallet_outlined,
          title: 'greenyield_wallet'.tr(),
          subtitle: 'payments_checkout_wallet_balance'.tr(
            namedArgs: {'amount': _money(walletBalance)},
          ),
          selected: walletSelected,
          onTap: () => onMethodChanged(CheckoutPaymentMethod.wallet),
        ),
        if (walletSelected && walletLow)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: theme.colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'payments_checkout_wallet_low'.tr(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const TopUpScreen()),
                  ),
                  child: Text('payments_checkout_top_up'.tr()),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        _OptionTile(
          icon: Icons.credit_card_outlined,
          title: 'card_payment'.tr(),
          selected: !walletSelected,
          onTap: () => onMethodChanged(CheckoutPaymentMethod.card),
        ),
        if (!walletSelected) ...[
          const SizedBox(height: 8),
          cardsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => Column(
              children: [
                Text(
                  error is PaymentException
                      ? error.message
                      : 'payments_load_error'.tr(),
                  textAlign: TextAlign.center,
                ),
                TextButton.icon(
                  onPressed: () => ref.invalidate(linkedCardsProvider),
                  icon: const Icon(Icons.refresh),
                  label: Text('payments_retry'.tr()),
                ),
              ],
            ),
            data: (cards) {
              final all = <LinkedCard>[...cards];
              if (extraCard != null &&
                  !all.any((card) => card.id == extraCard!.id)) {
                all.add(extraCard!);
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (all.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'payments_checkout_no_cards'.tr(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  for (final card in all)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _OptionTile(
                        leading: CardBrandIcon(brand: card.brand, width: 38),
                        title: card.title,
                        subtitle: card.isExpired
                            ? 'payments_expired_badge'.tr()
                            : '${card.maskedNumber}  ·  ${card.expiryLabel}',
                        subtitleIsError: card.isExpired,
                        selected: selectedCard?.id == card.id,
                        onTap: card.isExpired
                            ? null
                            : () => onCardSelected(card),
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: () => _addCard(context, ref),
                    icon: const Icon(Icons.add),
                    label: Text('payments_checkout_add_card'.tr()),
                  ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }
}

class _OptionTile extends StatelessWidget {
  final IconData? icon;
  final Widget? leading;
  final String title;
  final String? subtitle;
  final bool subtitleIsError;
  final bool selected;
  final VoidCallback? onTap;

  const _OptionTile({
    this.icon,
    this.leading,
    required this.title,
    this.subtitle,
    this.subtitleIsError = false,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.6 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
                : theme.colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              leading ?? Icon(icon, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: subtitleIsError
                              ? theme.colorScheme.error
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

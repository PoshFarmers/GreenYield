import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_secondary_header.dart';
import '../linked_card_service.dart';
import '../models/linked_card.dart';
import '../payment_gateway.dart';
import '../payment_providers.dart';
import 'add_card_sheet.dart';
import 'widgets/linked_card_tile.dart';

/// Manage saved cards: add, set default, remove. Online-only.
class PaymentMethodsScreen extends ConsumerStatefulWidget {
  const PaymentMethodsScreen({super.key});

  @override
  ConsumerState<PaymentMethodsScreen> createState() =>
      _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends ConsumerState<PaymentMethodsScreen> {
  bool _busy = false;

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _addCard() async {
    final card = await showAddCardSheet(context);
    if (card == null || !mounted) return;
    ref.invalidate(linkedCardsProvider);
    _snack('payments_card_added'.tr());
  }

  Future<void> _run(Future<void> Function() action, String successKey) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(linkedCardsProvider);
      _snack(successKey.tr());
    } on PaymentException catch (error) {
      _snack(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmRemove(LinkedCard card) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('payments_remove_confirm_title'.tr()),
        content: Text(
          'payments_remove_confirm_body'.tr(namedArgs: {'card': card.title}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('cancel'.tr()),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('payments_remove'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(
      () => ref.read(linkedCardServiceProvider).remove(card.id),
      'payments_removed',
    );
  }

  Future<void> _refresh() async {
    try {
      ref.invalidate(linkedCardsProvider);
      await ref.read(linkedCardsProvider.future);
    } catch (_) {
      // The error state renders from the provider itself.
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardsAsync = ref.watch(linkedCardsProvider);
    final cards = cardsAsync.asData?.value;
    final isFull =
        cards != null && cards.length >= LinkedCardService.maxSavedCards;
    final canAdd = cards != null && !isFull && !_busy;

    return Scaffold(
      appBar: AppSecondaryHeader(title: 'payments_methods_title'.tr()),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              children: [
                Expanded(
                  child: cardsAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, _) => _ErrorState(
                      message: error is PaymentException
                          ? error.message
                          : 'payments_load_error'.tr(),
                      onRetry: () => ref.invalidate(linkedCardsProvider),
                    ),
                    data: _buildList,
                  ),
                ),
                _AddCardBar(
                  isFull: isFull,
                  onPressed: canAdd ? _addCard : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildList(List<LinkedCard> cards) {
    final theme = Theme.of(context);

    if (cards.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
          children: [
            Icon(
              Icons.credit_card_off_outlined,
              size: 56,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'payments_no_cards_title'.tr(),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'payments_no_cards_subtitle'.tr(),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        children: [
          Text(
            'payments_cards_count'.tr(
              namedArgs: {
                'count': '${cards.length}',
                'max': '${LinkedCardService.maxSavedCards}',
              },
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          for (final card in cards) ...[
            LinkedCardTile(
              card: card,
              enabled: !_busy,
              onSetDefault: () => _run(
                () => ref.read(linkedCardServiceProvider).setDefault(card.id),
                'payments_default_updated',
              ),
              onRemove: () => _confirmRemove(card),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _AddCardBar extends StatelessWidget {
  final bool isFull;
  final VoidCallback? onPressed;

  const _AddCardBar({required this.isFull, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isFull) ...[
            Text(
              'payments_limit_hint'.tr(
                namedArgs: {'max': '${LinkedCardService.maxSavedCards}'},
              ),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
          ],
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onPressed,
              icon: const Icon(Icons.add),
              label: Text('payments_add_card'.tr()),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 48,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: Text('payments_retry'.tr()),
          ),
        ],
      ),
    );
  }
}

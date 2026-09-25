import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/widgets/app_secondary_header.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../payments/linked_card_service.dart';
import '../../payments/models/linked_card.dart';
import '../../payments/payment_gateway.dart';
import '../../payments/payment_providers.dart';
import '../../payments/presentation/add_card_sheet.dart';
import '../../payments/presentation/widgets/card_brand_icon.dart';
import '../wallet_service.dart';
import '../withdrawal_models.dart';
import 'withdrawal_history_screen.dart';

// Replaced by the shared money formatter in Task 15.
String _money(num value) => 'LKR ${NumberFormat('#,##0.00').format(value)}';

enum _Stage { form, processing, success, failure }

/// Withdraws wallet balance to a saved card. Pops `true` after a successful
/// withdrawal.
class WithdrawScreen extends ConsumerStatefulWidget {
  final String profileId;

  const WithdrawScreen({super.key, required this.profileId});

  @override
  ConsumerState<WithdrawScreen> createState() => _WithdrawScreenState();
}

class _WithdrawScreenState extends ConsumerState<WithdrawScreen> {
  final _service = const WalletService();
  final _amountCtl = TextEditingController();
  StreamSubscription<dynamic>? _balanceSub;

  double _balance = 0;
  String? _cardId;

  /// Idempotency key of the attempt in flight. Kept only while the outcome is
  /// unknown (network failure); cleared after any definitive result and when
  /// the amount or card changes.
  String? _requestId;

  _Stage _stage = _Stage.form;
  WithdrawalResult? _result;
  double _lastAmount = 0;
  LinkedCard? _lastCard;
  String? _error;

  @override
  void initState() {
    super.initState();
    _balanceSub = _service.watchBalance(widget.profileId).listen((wallet) {
      if (mounted) setState(() => _balance = wallet?.balance ?? 0);
    });
  }

  @override
  void dispose() {
    _balanceSub?.cancel();
    _amountCtl.dispose();
    super.dispose();
  }

  double? get _amount => double.tryParse(_amountCtl.text.trim());

  String? get _amountError {
    final amount = _amount;
    if (amount == null) return null;
    if (amount < WalletService.minWithdrawal) {
      return 'payments_error_withdrawal_amount_too_low'.tr();
    }
    if (amount > WalletService.maxWithdrawalPerDay) {
      return 'payments_error_withdrawal_daily_limit_exceeded'.tr();
    }
    if (amount > _balance) {
      return 'payments_error_withdrawal_insufficient_balance'.tr();
    }
    return null;
  }

  LinkedCard? _selectedCard(List<LinkedCard>? cards) {
    if (cards == null) return null;
    final usable = cards.where((card) => !card.isExpired).toList();
    for (final card in usable) {
      if (card.id == _cardId) return card;
    }
    for (final card in usable) {
      if (card.isDefault) return card;
    }
    return usable.isEmpty ? null : usable.first;
  }

  void _onAmountChanged() {
    setState(() {
      _requestId = null;
      _error = null;
    });
  }

  void _fillMax() {
    final max = _balance < WalletService.maxWithdrawalPerDay
        ? _balance
        : WalletService.maxWithdrawalPerDay;
    _amountCtl.text = (max * 100).floor() % 100 == 0
        ? max.toStringAsFixed(0)
        : max.toStringAsFixed(2);
    _onAmountChanged();
  }

  void _pickCard(LinkedCard card) {
    setState(() {
      _cardId = card.id;
      _requestId = null;
      _error = null;
    });
  }

  Future<void> _addCard() async {
    final card = await showAddCardSheet(context);
    if (card == null || !mounted) return;
    ref.invalidate(linkedCardsProvider);
    setState(() {
      _cardId = card.id;
      _requestId = null;
    });
  }

  Future<void> _submit(LinkedCard card, double amount) async {
    _requestId ??= const Uuid().v4();
    _lastAmount = amount;
    _lastCard = card;
    setState(() {
      _stage = _Stage.processing;
      _error = null;
    });

    try {
      final result = await _service.withdraw(
        cardId: card.id,
        amount: amount,
        requestId: _requestId!,
      );
      if (!mounted) return;
      _requestId = null;
      ref.invalidate(withdrawalsProvider);
      setState(() {
        _result = result;
        _stage = result.succeeded ? _Stage.success : _Stage.failure;
      });
    } on PaymentException catch (error) {
      if (!mounted) return;
      // `network` = unknown outcome: keep the request id so a retry is safe.
      final unknownOutcome = error.code == 'network';
      if (!unknownOutcome) _requestId = null;
      setState(() {
        _stage = _Stage.form;
        _error = unknownOutcome
            ? 'payments_withdraw_network_retry'.tr()
            : error.message;
      });
    }
  }

  void _tryAgain() {
    setState(() {
      _stage = _Stage.form;
      _error = null;
      _requestId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _stage != _Stage.processing,
      child: Scaffold(
        appBar: AppSecondaryHeader(
          title: 'payments_withdraw_title'.tr(),
          showBackButton: _stage != _Stage.processing,
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: switch (_stage) {
                _Stage.form => _buildForm(context),
                _Stage.processing => _buildProcessing(context),
                _Stage.success => _buildSuccess(context),
                _Stage.failure => _buildFailure(context),
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final theme = Theme.of(context);
    final cardsAsync = ref.watch(linkedCardsProvider);
    final selected = _selectedCard(cardsAsync.asData?.value);
    final amount = _amount;
    final amountError = _amountError;
    final canSubmit = selected != null && amount != null && amountError == null;
    final fee = WalletService.withdrawalFee;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(
                    alpha: 0.4,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'payments_withdraw_available'.tr(),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      _money(_balance),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: AppTextField(
                      label: 'payments_withdraw_amount'.tr(),
                      controller: _amountCtl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      prefixText: 'LKR ',
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d{0,7}(\.\d{0,2})?$'),
                        ),
                      ],
                      onChanged: (_) => _onAmountChanged(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: TextButton(
                      onPressed: _balance > 0 ? _fillMax : null,
                      child: Text('payments_withdraw_max'.tr()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                amountError ?? 'payments_withdraw_limits'.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: amountError != null
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'payments_withdraw_to'.tr(),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              _buildCards(context, cardsAsync, selected),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
        Container(
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
              if (canSubmit) ...[
                _DetailRow(
                  label: 'payments_withdraw_fee'.tr(),
                  value: _money(fee),
                ),
                const SizedBox(height: 4),
                _DetailRow(
                  label: 'payments_withdraw_net'.tr(),
                  value: _money(amount - fee),
                  bold: true,
                ),
                const SizedBox(height: 10),
              ],
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: canSubmit ? () => _submit(selected, amount) : null,
                  child: Text(
                    canSubmit
                        ? 'payments_withdraw_confirm'.tr(
                            namedArgs: {'amount': _money(amount)},
                          )
                        : 'payments_withdraw_button'.tr(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCards(
    BuildContext context,
    AsyncValue<List<LinkedCard>> cardsAsync,
    LinkedCard? selected,
  ) {
    final theme = Theme.of(context);

    return cardsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
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
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: () => ref.invalidate(linkedCardsProvider),
            icon: const Icon(Icons.refresh),
            label: Text('payments_retry'.tr()),
          ),
        ],
      ),
      data: (cards) {
        final isFull = cards.length >= LinkedCardService.maxSavedCards;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (cards.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'payments_withdraw_no_cards'.tr(),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            for (final card in cards) ...[
              _CardOption(
                card: card,
                selected: selected?.id == card.id,
                onTap: card.isExpired ? null : () => _pickCard(card),
              ),
              const SizedBox(height: 10),
            ],
            OutlinedButton.icon(
              onPressed: isFull ? null : _addCard,
              icon: const Icon(Icons.add),
              label: Text('payments_withdraw_add_card'.tr()),
            ),
          ],
        );
      },
    );
  }

  Widget _buildProcessing(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          Text(
            'payments_withdraw_processing'.tr(),
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }

  Widget _buildSuccess(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result!;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Spacer(),
          Icon(Icons.check_circle, size: 72, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            'payments_withdraw_success_title'.tr(),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'payments_withdraw_success_body'.tr(
              namedArgs: {
                'amount': _money(result.netAmount),
                'card': _lastCard?.title ?? '',
              },
            ),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                _DetailRow(
                  label: 'payments_withdraw_new_balance'.tr(),
                  value: _money(result.newBalance),
                ),
                if (result.gatewayReference != null) ...[
                  const SizedBox(height: 8),
                  _DetailRow(
                    label: 'payments_withdraw_reference'.tr(),
                    value: result.gatewayReference!,
                  ),
                ],
              ],
            ),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text('payments_withdraw_done'.tr()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFailure(BuildContext context) {
    final theme = Theme.of(context);
    final reason = PaymentException(_result?.failureCode ?? 'unknown').message;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Spacer(),
          Icon(Icons.error_outline, size: 72, color: theme.colorScheme.error),
          const SizedBox(height: 16),
          Text(
            'payments_withdraw_failed_title'.tr(),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            reason,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'payments_withdraw_failed_body'.tr(
              namedArgs: {'amount': _money(_lastAmount)},
            ),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _tryAgain,
              child: Text('payments_withdraw_try_again'.tr()),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('cancel'.tr()),
          ),
        ],
      ),
    );
  }
}

class _CardOption extends StatelessWidget {
  final LinkedCard card;
  final bool selected;
  final VoidCallback? onTap;

  const _CardOption({
    required this.card,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surfaceContainerLowest,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: ListTile(
        enabled: onTap != null,
        onTap: onTap,
        leading: CardBrandIcon(brand: card.brand),
        title: Text(
          card.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: card.isExpired
            ? Text(
                'payments_expired_badge'.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              )
            : Text('${card.maskedNumber}  ·  ${card.expiryLabel}'),
        trailing: Icon(
          selected ? Icons.check_circle : Icons.radio_button_unchecked,
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.outline,
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;

  const _DetailRow({
    required this.label,
    required this.value,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

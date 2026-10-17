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

// Replaced by the shared money formatter in Task 15.
String _money(num value) => 'LKR ${NumberFormat('#,##0.00').format(value)}';
String _moneyShort(num value) => 'LKR ${NumberFormat('#,##0').format(value)}';

enum _Stage { form, processing, success, failure }

/// Tops up the wallet from a saved card. Pops with `true` after a successful
/// top-up.
class TopUpScreen extends ConsumerStatefulWidget {
  const TopUpScreen({super.key});

  @override
  ConsumerState<TopUpScreen> createState() => _TopUpScreenState();
}

class _TopUpScreenState extends ConsumerState<TopUpScreen> {
  final _service = const WalletService();
  final _custom = TextEditingController();

  double? _preset;
  String? _cardId;

  /// Idempotency key of the attempt in flight. Kept only while the outcome is
  /// unknown (network failure) so a retry can't double-charge; cleared after
  /// any definitive result and whenever the amount or card changes.
  String? _requestId;

  _Stage _stage = _Stage.form;
  TopUpResult? _result;
  String? _error;

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  double? get _amount {
    final text = _custom.text.trim();
    if (text.isNotEmpty) return double.tryParse(text);
    return _preset;
  }

  String? get _amountError {
    final amount = _amount;
    if (amount == null) return null;
    if (amount < WalletService.minTopUp) {
      return 'payments_error_amount_too_low'.tr();
    }
    if (amount > WalletService.maxTopUp) {
      return 'payments_error_amount_too_high'.tr();
    }
    return null;
  }

  /// The chosen card if still usable, else the default, else the first usable.
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

  void _pickPreset(double value) {
    _custom.clear();
    setState(() {
      _preset = value;
      _requestId = null;
      _error = null;
    });
  }

  void _onCustomChanged() {
    setState(() {
      _preset = null;
      _requestId = null;
      _error = null;
    });
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
    setState(() {
      _stage = _Stage.processing;
      _error = null;
    });

    try {
      final result = await _service.topUpWithCard(
        cardId: card.id,
        amount: amount,
        requestId: _requestId!,
      );
      if (!mounted) return;
      _requestId = null;
      setState(() {
        _result = result;
        _stage = result.succeeded ? _Stage.success : _Stage.failure;
      });
    } on PaymentException catch (error) {
      if (!mounted) return;
      // `network` means we don't know whether the charge went through: keep
      // the request id so retrying is safe. Anything else is definitive.
      final unknownOutcome = error.code == 'network';
      if (!unknownOutcome) _requestId = null;
      setState(() {
        _stage = _Stage.form;
        _error = unknownOutcome
            ? 'payments_topup_network_retry'.tr()
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
          title: 'payments_topup_title'.tr(),
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

  // ---------------------------------------------------------------- form

  Widget _buildForm(BuildContext context) {
    final theme = Theme.of(context);
    final cardsAsync = ref.watch(linkedCardsProvider);
    final selected = _selectedCard(cardsAsync.asData?.value);
    final amount = _amount;
    final amountError = _amountError;
    final canSubmit = selected != null && amount != null && amountError == null;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'payments_topup_amount'.tr(),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final preset in WalletService.topUpPresets)
                    ChoiceChip(
                      label: Text(_moneyShort(preset)),
                      selected:
                          _custom.text.trim().isEmpty && _preset == preset,
                      onSelected: (_) => _pickPreset(preset),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              AppTextField(
                label: 'payments_topup_amount_custom'.tr(),
                controller: _custom,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                hintText: 'payments_topup_amount_hint'.tr(),
                prefixText: 'LKR ',
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'^\d{0,7}(\.\d{0,2})?$'),
                  ),
                ],
                onChanged: (_) => _onCustomChanged(),
              ),
              if (amountError != null) ...[
                const SizedBox(height: 6),
                Text(
                  amountError,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Text(
                'payments_topup_pay_with'.tr(),
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
                Text(
                  'payments_topup_summary'.tr(
                    namedArgs: {
                      'amount': _money(amount),
                      'card': selected.title,
                    },
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
                child: ElevatedButton(
                  onPressed: canSubmit ? () => _submit(selected, amount) : null,
                  child: Text(
                    canSubmit
                        ? 'payments_topup_confirm'.tr(
                            namedArgs: {'amount': _money(amount)},
                          )
                        : 'top_up'.tr(),
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
                  'payments_topup_no_cards'.tr(),
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
              label: Text('payments_topup_add_card'.tr()),
            ),
            if (isFull) ...[
              const SizedBox(height: 6),
              Text(
                'payments_limit_hint'.tr(
                  namedArgs: {'max': '${LinkedCardService.maxSavedCards}'},
                ),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  // ---------------------------------------------------- processing/result

  Widget _buildProcessing(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          Text(
            'payments_topup_processing'.tr(),
            style: theme.textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }

  Widget _buildSuccess(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result!;
    final amount = _amount ?? 0;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Spacer(),
          Icon(Icons.check_circle, size: 72, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            'payments_topup_success_title'.tr(),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'payments_topup_success_body'.tr(
              namedArgs: {'amount': _money(amount)},
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
                  label: 'payments_topup_new_balance'.tr(),
                  value: _money(result.newBalance),
                ),
                if (result.gatewayReference != null) ...[
                  const SizedBox(height: 8),
                  _DetailRow(
                    label: 'payments_topup_reference'.tr(),
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
              child: Text('payments_topup_done'.tr()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFailure(BuildContext context) {
    final theme = Theme.of(context);
    final message = PaymentException(_result?.failureCode ?? 'unknown').message;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Spacer(),
          Icon(Icons.error_outline, size: 72, color: theme.colorScheme.error),
          const SizedBox(height: 16),
          Text(
            'payments_topup_failed_title'.tr(),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _tryAgain,
              child: Text('payments_topup_try_again'.tr()),
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

  const _DetailRow({required this.label, required this.value});

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
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

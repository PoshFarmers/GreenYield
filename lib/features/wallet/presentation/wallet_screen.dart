import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../core/widgets/app_secondary_header.dart';
import '../../../models/wallet.dart';
import '../../payments/presentation/payment_methods_screen.dart';
import '../wallet_service.dart';
import 'top_up_screen.dart';
import 'withdraw_screen.dart';
import 'withdrawal_history_screen.dart';

/// Shared wallet screen for any role — shows the live balance, a
/// "Top Up" action (card-funded, see [TopUpScreen]), and a scrollable
/// list of recent transactions.
class WalletScreen extends StatefulWidget {
  final String profileId;

  const WalletScreen({super.key, required this.profileId});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  final _service = const WalletService();

  void _openTopUp() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const TopUpScreen()));
  }

  void _openWithdraw() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WithdrawScreen(profileId: widget.profileId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppSecondaryHeader(title: 'wallet_title'.tr()),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: StreamBuilder<Wallet?>(
              stream: _service.watchBalance(widget.profileId),
              builder: (context, walletSnapshot) {
                final wallet = walletSnapshot.data;
                final balanceText = wallet == null
                    ? 'LKR 0.00'
                    : '${wallet.currency} ${wallet.balance.toStringAsFixed(2)}';

                return ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer.withValues(
                          alpha: 0.4,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'current_balance'.tr(),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            balanceText,
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _openTopUp,
                                  icon: const Icon(Icons.add),
                                  label: Text('top_up'.tr()),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _openWithdraw,
                                  icon: const Icon(Icons.arrow_upward),
                                  label: Text('payments_withdraw_button'.tr()),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const PaymentMethodsScreen(),
                        ),
                      ),
                      icon: const Icon(Icons.credit_card_outlined),
                      label: Text('payments_methods_title'.tr()),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const WithdrawalHistoryScreen(),
                        ),
                      ),
                      icon: const Icon(Icons.history),
                      label: Text('payments_withdraw_history'.tr()),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'recent_transactions'.tr(),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    StreamBuilder<List<WalletTransaction>>(
                      stream: _service.watchTransactions(widget.profileId),
                      builder: (context, txnSnapshot) {
                        final transactions = txnSnapshot.data ?? [];
                        if (transactions.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: Text(
                                'no_transactions_yet'.tr(),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          );
                        }
                        return Column(
                          children: transactions
                              .map((txn) => _TransactionTile(transaction: txn))
                              .toList(),
                        );
                      },
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final WalletTransaction transaction;

  const _TransactionTile({required this.transaction});

  String get _labelKey => switch (transaction.type) {
    WalletTransactionType.topup => 'transaction_type_topup',
    WalletTransactionType.payment => 'transaction_type_payment',
    WalletTransactionType.payout => 'transaction_type_payout',
    WalletTransactionType.refund => 'transaction_type_refund',
    WalletTransactionType.withdrawal => 'transaction_type_withdrawal',
    WalletTransactionType.adjustment => 'transaction_type_adjustment',
  };

  IconData get _icon => switch (transaction.type) {
    WalletTransactionType.topup => Icons.add_circle_outline,
    WalletTransactionType.payment => Icons.shopping_cart_outlined,
    WalletTransactionType.payout => Icons.local_shipping_outlined,
    WalletTransactionType.refund => Icons.undo_outlined,
    WalletTransactionType.withdrawal => Icons.arrow_upward_outlined,
    WalletTransactionType.adjustment => Icons.tune_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCredit = transaction.amount >= 0;
    final amountColor = isCredit
        ? Colors.green.shade700
        : theme.colorScheme.error;
    final amountText =
        '${isCredit ? '+' : ''}${transaction.amount.toStringAsFixed(2)}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            child: Icon(_icon, size: 18, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_labelKey.tr(), style: theme.textTheme.bodyMedium),
                Text(
                  '${transaction.createdAt.year}-${transaction.createdAt.month.toString().padLeft(2, '0')}-${transaction.createdAt.day.toString().padLeft(2, '0')}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            amountText,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: amountColor,
            ),
          ),
        ],
      ),
    );
  }
}

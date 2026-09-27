import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/widgets/app_secondary_header.dart';
import '../../../models/wallet.dart';
import '../../orders/presentation/order_detail_screen.dart';
import '../wallet_history.dart';

class WalletTransactionDetailScreen extends StatelessWidget {
  final WalletTransaction transaction;

  const WalletTransactionDetailScreen({super.key, required this.transaction});

  num? _num(String key) => transaction.metadata[key] as num?;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = transaction;
    final m = t.metadata;
    final title = walletTxnTitle(t);
    final isCredit = t.amount >= 0;
    final local = t.createdAt.toLocal();
    final orderId = m['order_id'] as String?;
    final orderDisplay = m['order_display_id'] as String?;
    final role = walletOrderViewerRole(t);
    final gateway = m['gateway_reference'] as String?;
    final card = walletCardLabel(m);
    final note = t.description?.trim();
    final idShort = t.id.replaceAll('-', '');

    final rows = <Widget>[
      _Row(
        label: 'payments_wallet_detail_type'.tr(),
        value: 'transaction_type_${t.type.name}'.tr(),
      ),
      _Row(
        label: 'payments_wallet_detail_date'.tr(),
        value: DateFormat.yMMMd(context.locale.toString())
            .add_jm()
            .format(local),
      ),
      _Row(
        label: 'payments_wallet_detail_id'.tr(),
        value:
            'TX-${(idShort.length >= 8 ? idShort.substring(0, 8) : idShort).toUpperCase()}',
        copyable: true,
      ),
      if (orderDisplay != null)
        _Row(label: 'payments_wallet_detail_order'.tr(), value: orderDisplay),
      if (t.type == WalletTransactionType.payout &&
          t.referenceTable == 'orders' &&
          _num('gross') != null) ...[
        _Row(
          label: 'payments_wallet_detail_gross'.tr(),
          value: walletMoney(_num('gross')!),
        ),
        _Row(
          label: 'payments_commission'.tr(),
          value: '- ${walletMoney(_num('commission') ?? 0)}',
        ),
        _Row(
          label: 'payments_net_payout'.tr(),
          value: walletMoney(_num('net') ?? t.amount),
        ),
      ],
      if (card.isNotEmpty)
        _Row(label: 'payments_wallet_detail_card'.tr(), value: card),
      if (gateway != null && gateway.isNotEmpty)
        _Row(
          label: 'payments_wallet_detail_gateway'.tr(),
          value: gateway,
          copyable: true,
        ),
      _Row(
        label: 'payments_wallet_detail_balance_after'.tr(),
        value: walletMoney(t.balanceAfter),
      ),
      if (isWithdrawalReversal(t))
        _Row(
          label: 'payments_wallet_detail_note'.tr(),
          value: 'payments_wallet_reversal_note'.tr(),
        )
      else if (note != null && note.isNotEmpty && note != title)
        _Row(label: 'payments_wallet_detail_note'.tr(), value: note),
    ];

    return Scaffold(
      appBar: AppSecondaryHeader(title: 'payments_wallet_detail_title'.tr()),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Column(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Icon(
                        walletTxnIcon(t),
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${isCredit ? '+' : '-'} ${walletMoney(t.amount.abs())}',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isCredit
                            ? theme.colorScheme.primary
                            : theme.colorScheme.error,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Column(children: rows),
                ),
                if (orderId != null && role != null) ...[
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => OrderDetailScreen(
                          orderId: orderId,
                          viewerRole: role,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: Text('payments_wallet_detail_view_order'.tr()),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final bool copyable;

  const _Row({required this.label, required this.value, this.copyable = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (copyable)
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('payments_wallet_detail_copied'.tr()),
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
              child: const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(Icons.copy, size: 16),
              ),
            ),
        ],
      ),
    );
  }
}

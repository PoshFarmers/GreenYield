import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../core/local_db/powersync.dart';
import '../../models/wallet.dart';
import '../payments/models/linked_card.dart';

// Replaced by the shared money formatter in Task 15.
String walletMoney(num value) =>
    'LKR ${NumberFormat('#,##0.00').format(value)}';

enum WalletFilter {
  all('payments_wallet_filter_all', []),
  topups('payments_wallet_filter_topups', [WalletTransactionType.topup]),
  payments('payments_wallet_filter_payments', [WalletTransactionType.payment]),
  payouts('payments_wallet_filter_payouts', [WalletTransactionType.payout]),
  refunds('payments_wallet_filter_refunds', [WalletTransactionType.refund]),
  // `adjustment` rows only come from reversed (failed) withdrawals.
  withdrawals('payments_wallet_filter_withdrawals', [
    WalletTransactionType.withdrawal,
    WalletTransactionType.adjustment,
  ]);

  final String labelKey;
  final List<WalletTransactionType> types;

  const WalletFilter(this.labelKey, this.types);
}

class WalletMonthSummary {
  final double moneyIn;
  final double moneyOut;

  const WalletMonthSummary({this.moneyIn = 0, this.moneyOut = 0});
}

bool isWithdrawalReversal(WalletTransaction t) =>
    t.type == WalletTransactionType.adjustment &&
    t.metadata['reason'] == 'payout_failed';

String walletCardLabel(Map<String, dynamic> metadata) {
  final last4 = metadata['card_last4'];
  if (last4 == null) return '';
  return '${CardBrand.fromDb(metadata['card_brand'] as String?).label} •••• $last4';
}

String walletTxnTitle(WalletTransaction t) {
  final m = t.metadata;
  final order = m['order_display_id'] as String?;
  final card = walletCardLabel(m);
  if (isWithdrawalReversal(t)) return 'payments_wallet_title_reversal'.tr();

  switch (t.type) {
    case WalletTransactionType.topup:
      if (card.isNotEmpty) {
        return 'payments_wallet_title_topup_card'.tr(namedArgs: {'card': card});
      }
    case WalletTransactionType.payment:
      if (order != null) {
        return 'payments_wallet_title_payment_order'.tr(
          namedArgs: {'order': order},
        );
      }
    case WalletTransactionType.payout:
      if (order != null) {
        return (t.referenceTable == 'delivery'
                ? 'payments_wallet_title_delivery_payout'
                : 'payments_wallet_title_payout_order')
            .tr(namedArgs: {'order': order});
      }
    case WalletTransactionType.refund:
      if (order != null) {
        return 'payments_wallet_title_refund_order'.tr(
          namedArgs: {'order': order},
        );
      }
    case WalletTransactionType.withdrawal:
      if (card.isNotEmpty) {
        return 'payments_wallet_title_withdrawal_card'.tr(
          namedArgs: {'card': card},
        );
      }
    case WalletTransactionType.adjustment:
      break;
  }
  final d = t.description?.trim();
  return (d != null && d.isNotEmpty)
      ? d
      : 'transaction_type_${t.type.name}'.tr();
}

IconData walletTxnIcon(WalletTransaction t) => switch (t.type) {
  WalletTransactionType.topup => Icons.add_circle_outline,
  WalletTransactionType.payment => Icons.shopping_cart_outlined,
  WalletTransactionType.payout => Icons.local_shipping_outlined,
  WalletTransactionType.refund => Icons.undo_outlined,
  WalletTransactionType.withdrawal => Icons.arrow_upward_outlined,
  WalletTransactionType.adjustment => Icons.tune_outlined,
};

/// Role to open the linked order as, derived from the transaction itself.
String? walletOrderViewerRole(WalletTransaction t) => switch (t.type) {
  WalletTransactionType.payment || WalletTransactionType.refund => 'buyer',
  WalletTransactionType.payout =>
    t.referenceTable == 'delivery' ? 'driver' : 'farmer',
  _ => null,
};

class WalletHistoryService {
  const WalletHistoryService();

  /// Newest first, optionally filtered by type. Reads the local mirror, so it
  /// works offline; grow [limit] to page.
  Stream<List<WalletTransaction>> watchTransactions(
    String profileId, {
    WalletFilter filter = WalletFilter.all,
    int limit = 30,
  }) {
    final types = filter.types.map((t) => t.name).toList();
    final inClause = types.isEmpty
        ? ''
        : 'AND wt.type IN (${List.filled(types.length, '?').join(', ')})';
    return db
        .watch(
          '''
          SELECT wt.* FROM wallet_transaction wt
          JOIN wallet w ON w.id = wt.wallet_id
          WHERE w.profile_id = ? $inClause
          ORDER BY wt.created_at DESC
          LIMIT ?
          ''',
          parameters: [profileId, ...types, limit],
        )
        .map((rows) => rows.map(WalletTransaction.fromMap).toList());
  }

  /// This calendar month (device time): money in / out. Failed withdrawals and
  /// their reversal are excluded from both sides (net effect is zero).
  Stream<WalletMonthSummary> watchMonthSummary(String profileId) {
    return db
        .watch(
          '''
          SELECT wt.* FROM wallet_transaction wt
          JOIN wallet w ON w.id = wt.wallet_id
          WHERE w.profile_id = ?
          ORDER BY wt.created_at DESC
          LIMIT 1000
          ''',
          parameters: [profileId],
        )
        .map((rows) {
          final txns = rows.map(WalletTransaction.fromMap).toList();
          final reversed = <String>{
            for (final t in txns)
              if (isWithdrawalReversal(t) &&
                  t.metadata['reverses_wallet_transaction_id'] != null)
                '${t.metadata['reverses_wallet_transaction_id']}',
          };
          final now = DateTime.now();
          var moneyIn = 0.0;
          var moneyOut = 0.0;
          for (final t in txns) {
            final local = t.createdAt.toLocal();
            if (local.year != now.year || local.month != now.month) continue;
            if (reversed.contains(t.id) || isWithdrawalReversal(t)) continue;
            if (t.amount >= 0) {
              moneyIn += t.amount;
            } else {
              moneyOut += -t.amount;
            }
          }
          return WalletMonthSummary(moneyIn: moneyIn, moneyOut: moneyOut);
        });
  }
}

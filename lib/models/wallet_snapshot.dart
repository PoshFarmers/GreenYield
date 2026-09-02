import 'package:flutter/foundation.dart';

/// Kind of row shown in "Recent Activity". Drives icon + amount sign.
enum WalletTransactionType { deliveryFee, payoutToBank }

@immutable
class WalletTransaction {
  final String id;
  final WalletTransactionType type;
  final int amount; // LKR, minor-unit-free (whole rupees) like the design
  final String? orderRef;
  final DateTime date;

  const WalletTransaction({
    required this.id,
    required this.type,
    required this.amount,
    this.orderRef,
    required this.date,
  });
}

/// Snapshot of a driver's wallet — balance, most recent payout, linked
/// bank, and recent activity. Mirrors Driver_Wallet.png.
///
/// There's no `wallet`/`payment`/`payout` read path wired up on the
/// client yet (`features/wallet` is still an empty stub, same caveat as
/// the `_WalletCard` placeholder on the driver profile screen), so this
/// is deliberately static sample data. The schema already has the
/// pieces to back this for real — `wallet`, `wallet_transaction`,
/// `payment`/`refund` (see the `supabase/migrations` wallet & payment
/// files) — so swapping in a real PowerSync-backed provider later only
/// touches this file, not `DriverWalletScreen`.
class WalletSnapshot {
  final int availableBalance;
  final int recentPayoutAmount;
  final DateTime recentPayoutExpectedArrival;
  final String bankName;
  final String bankAccountLast4;
  final List<WalletTransaction> recentActivity;

  const WalletSnapshot({
    required this.availableBalance,
    required this.recentPayoutAmount,
    required this.recentPayoutExpectedArrival,
    required this.bankName,
    required this.bankAccountLast4,
    required this.recentActivity,
  });
}

WalletSnapshot sampleWalletSnapshot() {
  final now = DateTime.now();
  return WalletSnapshot(
    availableBalance: 28400,
    recentPayoutAmount: 45000,
    recentPayoutExpectedArrival: DateTime(
      now.year,
      now.month,
      now.day + 1,
      14,
      0,
    ),
    bankName: 'Commercial Bank',
    bankAccountLast4: '4589',
    recentActivity: [
      WalletTransaction(
        id: 'txn-1',
        type: WalletTransactionType.deliveryFee,
        amount: 3200,
        orderRef: 'GY-8842',
        date: DateTime(now.year, now.month, now.day),
      ),
      WalletTransaction(
        id: 'txn-2',
        type: WalletTransactionType.payoutToBank,
        amount: -45000,
        date: DateTime(now.year, now.month, now.day - 1),
      ),
      WalletTransaction(
        id: 'txn-3',
        type: WalletTransactionType.deliveryFee,
        amount: 4500,
        orderRef: 'GY-8839',
        date: DateTime(now.year, now.month, now.day - 2),
      ),
    ],
  );
}

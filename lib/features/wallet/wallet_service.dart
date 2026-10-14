import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/local_db/powersync.dart'; // exposes `db`
import '../../core/supabase/client.dart';
import '../../models/wallet.dart';
import '../payments/payment_gateway.dart';

/// Outcome of `topup_wallet_with_card`. A gateway decline is a normal result
/// (`succeeded == false` plus a [failureCode]), not an exception.
class TopUpResult {
  final bool succeeded;
  final String? walletTransactionId;
  final String? gatewayReference;
  final double newBalance;
  final String? failureCode;

  const TopUpResult({
    required this.succeeded,
    this.walletTransactionId,
    this.gatewayReference,
    required this.newBalance,
    this.failureCode,
  });

  factory TopUpResult.fromMap(Map<String, dynamic> map) {
    return TopUpResult(
      succeeded: map['status'] == 'succeeded',
      walletTransactionId: map['wallet_transaction_id'] as String?,
      gatewayReference: map['gateway_reference'] as String?,
      newBalance: (map['new_balance'] as num?)?.toDouble() ?? 0,
      failureCode: map['failure_code'] as String?,
    );
  }
}

/// Wallet access. Reads watch the local PowerSync mirror (read-only —
/// balance/transaction writes all happen server-side via
/// `apply_wallet_transaction()`). The one write this class exposes,
/// [topUpWithCard], goes through the `topup_wallet_with_card` RPC.
class WalletService {
  const WalletService();

  /// Mirrors the server-side limits in `topup_wallet_with_card`.
  static const minTopUp = 100.0;
  static const maxTopUp = 100000.0;
  static const topUpPresets = [500.0, 1000.0, 2500.0, 5000.0];

  /// Null when the wallet row doesn't exist yet (no transactions ever
  /// posted) — treat as a balance of 0.
  Stream<Wallet?> watchBalance(String profileId) {
    return db
        .watch(
          'SELECT * FROM wallet WHERE profile_id = ?',
          parameters: [profileId],
        )
        .map((rows) => rows.isEmpty ? null : Wallet.fromMap(rows.first));
  }

  Stream<List<WalletTransaction>> watchTransactions(
    String profileId, {
    int limit = 50,
  }) {
    return db
        .watch(
          '''
          SELECT wt.* FROM wallet_transaction wt
          JOIN wallet w ON w.id = wt.wallet_id
          WHERE w.profile_id = ?
          ORDER BY wt.created_at DESC
          LIMIT ?
          ''',
          parameters: [profileId, limit],
        )
        .map((rows) => rows.map(WalletTransaction.fromMap).toList());
  }

  /// Charges [cardId] and credits the signed-in user's wallet.
  ///
  /// [requestId] is the idempotency key: reuse it only when retrying the SAME
  /// attempt after a network failure (the server then returns the stored
  /// result instead of charging twice). Use a fresh id for a new attempt.
  ///
  /// Throws [PaymentException] for validation problems (`amount_too_low`,
  /// `card_not_found`, ...) and `network` when the outcome is unknown.
  Future<TopUpResult> topUpWithCard({
    required String cardId,
    required double amount,
    required String requestId,
  }) async {
    try {
      final data = await supabase.rpc(
        'topup_wallet_with_card',
        params: {
          'p_linked_card_id': cardId,
          'p_amount': amount,
          'p_request_id': requestId,
        },
      );
      return TopUpResult.fromMap(Map<String, dynamic>.from(data as Map));
    } on PostgrestException catch (error) {
      throw PaymentException.fromServerMessage(error.message);
    } on Exception {
      throw const PaymentException('network');
    }
  }
}

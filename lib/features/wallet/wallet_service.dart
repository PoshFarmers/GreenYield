import '../../core/local_db/powersync.dart'; // exposes `db`
import '../../core/supabase/client.dart';
import '../../models/wallet.dart';

/// Wallet access. Reads watch the local PowerSync mirror (read-only —
/// balance/transaction writes all happen server-side via
/// `apply_wallet_transaction()`). The one write this class exposes,
/// [topUp], goes through the `topup_wallet` RPC rather than writing
/// to the wallet tables directly — see that migration's doc comment.
class WalletService {
  const WalletService();

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

  /// Credits the signed-in user's own wallet by [amount] LKR via the
  /// `topup_wallet` RPC. Throws on failure (e.g. invalid amount) —
  /// callers should catch and surface the error.
  Future<void> topUp(double amount) async {
    await supabase.rpc('topup_wallet', params: {'p_amount': amount});
  }
}

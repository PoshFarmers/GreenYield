import '../../core/local_db/powersync.dart'; // exposes `db`
import '../../models/wallet.dart';

/// Read-only wallet access. All writes happen server-side via
/// `apply_wallet_transaction()` (Sprint 2) — this class only watches
/// the local PowerSync mirror, same read-only pattern as
/// MarketPriceService.
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
}

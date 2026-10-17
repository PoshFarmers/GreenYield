import 'dart:convert';

enum WalletTransactionType {
  topup,
  payment,
  payout,
  refund,
  withdrawal,
  adjustment,
}

/// Unknown or missing types fall back to `adjustment` instead of throwing, so
/// a new server-side type can't break the whole wallet screen.
WalletTransactionType _typeFromDb(String? value) =>
    WalletTransactionType.values.firstWhere(
      (t) => t.name == value,
      orElse: () => WalletTransactionType.adjustment,
    );

/// `metadata` is jsonb server-side and arrives as a JSON string locally.
Map<String, dynamic> _metadataFromDb(Object? raw) {
  if (raw is Map) return Map<String, dynamic>.from(raw);
  if (raw is String && raw.isNotEmpty) {
    try {
      final decoded = json.decode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // Malformed metadata is treated as empty.
    }
  }
  return const {};
}

/// Mirrors the `wallet` table — one row per profile, lazily created by
/// `apply_wallet_transaction()` on first transaction. `null` in the UI
/// means the wallet row doesn't exist yet (balance is effectively 0).
class Wallet {
  final String id;
  final String profileId;
  final double balance;
  final String currency;
  final DateTime updatedAt;

  const Wallet({
    required this.id,
    required this.profileId,
    required this.balance,
    required this.currency,
    required this.updatedAt,
  });

  factory Wallet.fromMap(Map<String, dynamic> map) {
    return Wallet(
      id: map['id'] as String,
      profileId: map['profile_id'] as String,
      balance: (map['balance'] as num?)?.toDouble() ?? 0,
      currency: map['currency'] as String? ?? 'LKR',
      updatedAt:
          DateTime.tryParse(map['updated_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

/// Mirrors one row of `wallet_transaction`.
class WalletTransaction {
  final String id;
  final WalletTransactionType type;
  final double amount;
  final double balanceAfter;
  final String? referenceTable;
  final String? referenceId;
  final String? description;

  /// Structured details (gateway reference, card last4, order id, ...).
  final Map<String, dynamic> metadata;
  final DateTime createdAt;

  const WalletTransaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.balanceAfter,
    this.referenceTable,
    this.referenceId,
    this.description,
    this.metadata = const {},
    required this.createdAt,
  });

  factory WalletTransaction.fromMap(Map<String, dynamic> map) {
    return WalletTransaction(
      id: map['id'] as String,
      type: _typeFromDb(map['type'] as String?),
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      balanceAfter: (map['balance_after'] as num?)?.toDouble() ?? 0,
      referenceTable: map['reference_table'] as String?,
      referenceId: map['reference_id'] as String?,
      description: map['description'] as String?,
      metadata: _metadataFromDb(map['metadata']),
      createdAt:
          DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

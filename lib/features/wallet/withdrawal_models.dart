import '../payments/models/linked_card.dart';

double _num(dynamic value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

/// Outcome of `request_withdrawal`. A gateway failure is a normal result
/// (`succeeded == false`); the money has already been returned to the wallet.
class WithdrawalResult {
  final bool succeeded;
  final String? withdrawalId;
  final String? gatewayReference;
  final String? failureCode;
  final double amount;
  final double fee;
  final double netAmount;
  final double newBalance;

  const WithdrawalResult({
    required this.succeeded,
    this.withdrawalId,
    this.gatewayReference,
    this.failureCode,
    required this.amount,
    required this.fee,
    required this.netAmount,
    required this.newBalance,
  });

  factory WithdrawalResult.fromMap(Map<String, dynamic> map) {
    return WithdrawalResult(
      succeeded: map['status'] == 'completed',
      withdrawalId: map['withdrawal_id'] as String?,
      gatewayReference: map['gateway_reference'] as String?,
      failureCode: map['failure_code'] as String?,
      amount: _num(map['amount']),
      fee: _num(map['fee']),
      netAmount: _num(map['net_amount']),
      newBalance: _num(map['new_balance']),
    );
  }
}

/// One row of `list_withdrawals`.
class Withdrawal {
  final String id;
  final double amount;
  final double fee;
  final double netAmount;

  /// processing | completed | failed
  final String status;
  final String? failureCode;
  final String? gatewayReference;
  final CardBrand cardBrand;
  final String? cardLast4;
  final DateTime requestedAt;
  final DateTime? completedAt;

  const Withdrawal({
    required this.id,
    required this.amount,
    required this.fee,
    required this.netAmount,
    required this.status,
    this.failureCode,
    this.gatewayReference,
    required this.cardBrand,
    this.cardLast4,
    required this.requestedAt,
    this.completedAt,
  });

  factory Withdrawal.fromMap(Map<String, dynamic> map) {
    return Withdrawal(
      id: map['id'] as String,
      amount: _num(map['amount']),
      fee: _num(map['fee']),
      netAmount: _num(map['net_amount']),
      status: (map['status'] as String?) ?? 'processing',
      failureCode: map['failure_code'] as String?,
      gatewayReference: map['gateway_reference'] as String?,
      cardBrand: CardBrand.fromDb(map['card_brand'] as String?),
      cardLast4: map['card_last4'] as String?,
      requestedAt:
          DateTime.tryParse((map['requested_at'] as String?) ?? '')
              ?.toLocal() ??
          DateTime.now(),
      completedAt: DateTime.tryParse((map['completed_at'] as String?) ?? '')
          ?.toLocal(),
    );
  }
}

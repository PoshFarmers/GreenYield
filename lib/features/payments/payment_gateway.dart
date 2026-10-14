import 'package:easy_localization/easy_localization.dart';

import 'models/linked_card.dart';

/// Card details collected by the add-card form.
///
/// MOCK-ONLY NOTE: with the mock gateway the PAN travels to our backend (as an
/// RPC parameter, where it is validated and discarded, never stored). A real
/// gateway implementation must tokenize on the client so the PAN and CVC
/// never reach our servers.
class NewCardInput {
  final String number;
  final int expMonth;
  final int expYear;
  final String cvc;
  final String holderName;
  final String? nickname;
  final bool makeDefault;

  /// false = one-off card used at checkout: hidden from the saved list and
  /// not counted toward the card limit.
  final bool save;

  const NewCardInput({
    required this.number,
    required this.expMonth,
    required this.expYear,
    required this.cvc,
    required this.holderName,
    this.nickname,
    this.makeDefault = false,
    this.save = true,
  });
}

/// A failed payment operation, identified by a stable code that maps to a
/// localized `payments_error_<code>` message.
class PaymentException implements Exception {
  final String code;

  const PaymentException(this.code);

  static const _knownCodes = {
    'invalid_card_number',
    'invalid_expiry',
    'card_expired',
    'invalid_cvc',
    'invalid_holder_name',
    'invalid_nickname',
    'card_limit_reached',
    'card_already_added',
    'card_not_found',
    'card_declined',
    'insufficient_funds',
    'expired_card',
    'incorrect_cvc',
    'amount_too_low',
    'amount_too_high',
    'invalid_amount',
    'invalid_request',
    'request_id_conflict',
    'network',
  };

  /// The migration raises plain codes as the exception message.
  factory PaymentException.fromServerMessage(String message) {
    final code = message.trim();
    return PaymentException(_knownCodes.contains(code) ? code : 'unknown');
  }

  String get message {
    final key = 'payments_error_$code';
    final text = key.tr();
    return text == key ? 'payments_error_unknown'.tr() : text;
  }

  @override
  String toString() => 'PaymentException($code)';
}

/// The seam between the app and a payment gateway. Today only
/// [MockPaymentGateway] exists; swap it for a real implementation (e.g.
/// PayHere) without touching the UI.
///
/// Charges, payouts and refunds happen server-side inside SQL functions
/// (top-up, checkout, withdrawal), so this interface only covers card
/// management for now.
abstract class PaymentGateway {
  const PaymentGateway();

  Future<List<LinkedCard>> listCards();

  Future<LinkedCard> addCard(NewCardInput input);

  Future<void> removeCard(String cardId);

  Future<void> setDefaultCard(String cardId);
}

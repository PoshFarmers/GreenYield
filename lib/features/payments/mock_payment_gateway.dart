import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/client.dart';
import 'models/linked_card.dart';
import 'payment_gateway.dart';

/// Talks to the `mockgw_*`-backed RPCs from the Task 1 migration.
/// MOCK ONLY: replace with a real gateway implementation later.
class MockPaymentGateway extends PaymentGateway {
  const MockPaymentGateway();

  Future<dynamic> _guard(Future<dynamic> Function() call) async {
    try {
      return await call();
    } on PostgrestException catch (error) {
      throw PaymentException.fromServerMessage(error.message);
    } on Exception {
      throw const PaymentException('network');
    }
  }

  @override
  Future<List<LinkedCard>> listCards() async {
    final rows = await _guard(
      () async => await supabase.rpc('list_linked_cards'),
    );
    return (rows as List)
        .map((row) => LinkedCard.fromMap(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  @override
  Future<LinkedCard> addCard(NewCardInput input) async {
    // Never log these params: they contain the card number and CVC.
    final data = await _guard(
      () async => await supabase.rpc(
        'add_linked_card',
        params: {
          'p_number': input.number,
          'p_exp_month': input.expMonth,
          'p_exp_year': input.expYear,
          'p_cvc': input.cvc,
          'p_holder_name': input.holderName,
          'p_nickname': input.nickname,
          'p_make_default': input.makeDefault,
          'p_save': input.save,
        },
      ),
    );
    return LinkedCard.fromMap(Map<String, dynamic>.from(data as Map));
  }

  @override
  Future<void> removeCard(String cardId) async {
    await _guard(
      () async => await supabase.rpc(
        'remove_linked_card',
        params: {'p_card_id': cardId},
      ),
    );
  }

  @override
  Future<void> setDefaultCard(String cardId) async {
    await _guard(
      () async => await supabase.rpc(
        'set_default_linked_card',
        params: {'p_card_id': cardId},
      ),
    );
  }
}

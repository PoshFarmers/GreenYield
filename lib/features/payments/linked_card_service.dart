import 'models/linked_card.dart';
import 'payment_gateway.dart';

/// Card management on top of a [PaymentGateway]. Online-only: cards are never
/// synced to the device.
class LinkedCardService {
  /// Matches the server-side limit in `add_linked_card`.
  static const maxSavedCards = 5;

  final PaymentGateway _gateway;

  const LinkedCardService(this._gateway);

  Future<List<LinkedCard>> list() => _gateway.listCards();

  Future<LinkedCard> add(NewCardInput input) => _gateway.addCard(input);

  Future<void> remove(String cardId) => _gateway.removeCard(cardId);

  Future<void> setDefault(String cardId) => _gateway.setDefaultCard(cardId);
}

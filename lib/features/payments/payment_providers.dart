import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'linked_card_service.dart';
import 'mock_payment_gateway.dart';
import 'models/linked_card.dart';
import 'payment_gateway.dart';

/// The one place the gateway implementation is chosen.
final paymentGatewayProvider = Provider<PaymentGateway>(
  (ref) => const MockPaymentGateway(),
);

final linkedCardServiceProvider = Provider<LinkedCardService>(
  (ref) => LinkedCardService(ref.watch(paymentGatewayProvider)),
);

/// Saved cards for the signed-in user. Invalidate after any change.
final linkedCardsProvider = FutureProvider.autoDispose<List<LinkedCard>>(
  (ref) => ref.watch(linkedCardServiceProvider).list(),
);

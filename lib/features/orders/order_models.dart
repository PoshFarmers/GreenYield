import '../../models/cart_item.dart';
import '../../models/profile.dart';

/// One farmer's slice of a checkout — becomes one `orders` row (+ its
/// `order_item` rows + one `payment` row) once [CheckoutService.placeOrder]
/// runs. See [CheckoutService] for why this isn't a `sub_orders` table.
class CheckoutSubOrder {
  final String farmerProfileId;
  final List<CartLineItem> items;
  final double subtotal;
  final double deliveryFee;
  final double tax;

  const CheckoutSubOrder({
    required this.farmerProfileId,
    required this.items,
    required this.subtotal,
    required this.deliveryFee,
    required this.tax,
  });

  double get total => subtotal + deliveryFee + tax;
}

/// The full price breakdown for a checkout spanning one or more
/// farmers — what the checkout screen renders before the buyer
/// confirms, and what [CheckoutService.placeOrder] actually charges.
class CheckoutSummary {
  final List<CheckoutSubOrder> subOrders;

  const CheckoutSummary({required this.subOrders});

  double get subtotal => subOrders.fold(0, (sum, s) => sum + s.subtotal);
  double get deliveryFee => subOrders.fold(0, (sum, s) => sum + s.deliveryFee);
  double get tax => subOrders.fold(0, (sum, s) => sum + s.tax);
  double get total => subOrders.fold(0, (sum, s) => sum + s.total);
}

/// What [CheckoutService.placeOrder] hands back once every per-farmer
/// `orders` row has been written locally — everything the confirmation
/// screen needs to render, keyed by the shared `checkout_group_id`.
class PlacedOrderGroup {
  final String checkoutGroupId;
  final List<String> orderIds;
  final CheckoutSummary summary;
  final DateTime placedAt;
  final Address deliveryAddress;

  /// The buyer-selected delivery date (always tomorrow or later).
  /// Stored in `orders.order_date` on the server side.
  final DateTime orderDate;

  const PlacedOrderGroup({
    required this.checkoutGroupId,
    required this.orderIds,
    required this.summary,
    required this.placedAt,
    required this.deliveryAddress,
    required this.orderDate,
  });

  /// Short, human-friendly id for display — the full
  /// `checkout_group_id` UUID is what's actually stored, this is just
  /// how it's shown on the confirmation screen (mirrors the
  /// "GY-XXXX-A" style from the confirmation mock).
  String get displayId =>
      'GY-${checkoutGroupId.replaceAll('-', '').substring(0, 6).toUpperCase()}';

  int get farmerCount => summary.subOrders.length;
}

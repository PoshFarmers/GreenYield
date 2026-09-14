import 'package:flutter/material.dart';

import '../../order_detail_models.dart';

/// Color-coded pill badge for an [OrderStatus].
/// Matches the design in the mockups: green for positive states,
/// amber for in-progress, grey for terminal.
class OrderStatusChip extends StatelessWidget {
  final OrderStatus status;
  final double fontSize;

  const OrderStatusChip({super.key, required this.status, this.fontSize = 11});

  @override
  Widget build(BuildContext context) {
    final (bg, fg, icon) = _palette(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: fg),
          const SizedBox(width: 4),
          Text(
            status.displayLabel,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  (Color bg, Color fg, IconData icon) _palette(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    switch (status) {
      case OrderStatus.placed:
        return (
          const Color(0xFFE8F5E9),
          const Color(0xFF388E3C),
          Icons.receipt_outlined,
        );
      case OrderStatus.confirmed:
        return (
          const Color(0xFFE3F2FD),
          const Color(0xFF1976D2),
          Icons.check_circle_outline,
        );
      case OrderStatus.assigned:
        return (
          const Color(0xFFFFF8E1),
          const Color(0xFFF57F17),
          Icons.person_pin_outlined,
        );
      case OrderStatus.packed:
        return (
          const Color(0xFFF3E5F5),
          const Color(0xFF7B1FA2),
          Icons.inventory_2_outlined,
        );
      case OrderStatus.pickedUp:
        return (
          const Color(0xFFE8F5E9),
          const Color(0xFF2E7D32),
          Icons.local_shipping_outlined,
        );
      case OrderStatus.inTransit:
        return (
          const Color(0xFFFFF3E0),
          const Color(0xFFE65100),
          Icons.directions_car_outlined,
        );
      case OrderStatus.delivered:
        return (cs.primaryContainer, cs.primary, Icons.check_circle_outline);
      case OrderStatus.completed:
        return (cs.primaryContainer, cs.primary, Icons.verified_outlined);
      case OrderStatus.cancelled:
        return (cs.errorContainer, cs.error, Icons.cancel_outlined);
    }
  }
}

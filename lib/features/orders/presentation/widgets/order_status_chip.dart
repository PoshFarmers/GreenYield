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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    switch (status) {
      case OrderStatus.placed:
        return (
          isDark ? const Color(0xFF1B3820) : const Color(0xFFE8F5E9),
          isDark ? const Color(0xFF81C784) : const Color(0xFF388E3C),
          Icons.receipt_outlined,
        );
      case OrderStatus.confirmed:
        return (
          isDark ? const Color(0xFF0D3256) : const Color(0xFFE3F2FD),
          isDark ? const Color(0xFF64B5F6) : const Color(0xFF1976D2),
          Icons.check_circle_outline,
        );
      case OrderStatus.assigned:
        return (
          isDark ? const Color(0xFF3E2F00) : const Color(0xFFFFF8E1),
          isDark ? const Color(0xFFFFD54F) : const Color(0xFFF57F17),
          Icons.person_pin_outlined,
        );
      case OrderStatus.packed:
        return (
          isDark ? const Color(0xFF331A3D) : const Color(0xFFF3E5F5),
          isDark ? const Color(0xFFBA68C8) : const Color(0xFF7B1FA2),
          Icons.inventory_2_outlined,
        );
      case OrderStatus.pickedUp:
        return (
          isDark ? const Color(0xFF16381C) : const Color(0xFFE8F5E9),
          isDark ? const Color(0xFF81C784) : const Color(0xFF2E7D32),
          Icons.local_shipping_outlined,
        );
      case OrderStatus.inTransit:
        return (
          isDark ? const Color(0xFF3E2000) : const Color(0xFFFFF3E0),
          isDark ? const Color(0xFFFFB74D) : const Color(0xFFE65100),
          Icons.directions_car_outlined,
        );
      case OrderStatus.delivered:
        return (
          isDark ? const Color(0xFF1B3820) : const Color(0xFFE8F5E9),
          isDark ? const Color(0xFF81C784) : const Color(0xFF1B5E20),
          Icons.verified_outlined,
        );
      case OrderStatus.completed:
        return (
          isDark ? const Color(0xFF1B3820) : const Color(0xFFE8F5E9),
          isDark ? const Color(0xFF81C784) : const Color(0xFF1B5E20),
          Icons.verified_outlined,
        );
      case OrderStatus.cancelled:
        return (cs.errorContainer, cs.error, Icons.cancel_outlined);
    }
  }
}

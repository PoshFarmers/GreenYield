import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../delivery_fee_service.dart';

/// buyer-facing price breakdown: farm-gate
/// subtotal (price/kg × quantity) plus an estimated delivery fee.
class PriceBreakdownCard extends StatefulWidget {
  final double pricePerKg;
  final double quantityKg;
  final double? distanceKm;

  const PriceBreakdownCard({
    super.key,
    required this.pricePerKg,
    required this.quantityKg,
    required this.distanceKm,
  });

  @override
  State<PriceBreakdownCard> createState() => _PriceBreakdownCardState();
}

class _PriceBreakdownCardState extends State<PriceBreakdownCard> {
  final _service = const DeliveryFeeService();

  double? _fee;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PriceBreakdownCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.distanceKm != widget.distanceKm) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final fee = await _service.estimateFee(widget.distanceKm);
    if (!mounted) return;
    setState(() {
      _fee = fee;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtotal = widget.pricePerKg * widget.quantityKg;
    final currency = 'currency_prefix'.tr();
    final fee = _fee;
    final total = fee == null ? subtotal : subtotal + fee;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _row(
          theme,
          'farm_gate_subtotal'.tr(),
          '$currency ${subtotal.toStringAsFixed(2)}',
        ),
        const SizedBox(height: 6),
        _isLoading
            ? Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'estimated_delivery_fee'.tr(),
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(
                    height: 14,
                    width: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              )
            : _row(
                theme,
                'estimated_delivery_fee'.tr(),
                fee == null
                    ? 'delivery_fee_unknown'.tr()
                    : '$currency ${fee.toStringAsFixed(2)}',
                valueColor: fee == null
                    ? theme.colorScheme.onSurfaceVariant
                    : null,
              ),
        const Divider(height: 20),
        _row(
          theme,
          'estimated_total'.tr(),
          '$currency ${total.toStringAsFixed(2)}',
          isBold: true,
        ),
        if (fee == null) ...[
          const SizedBox(height: 4),
          Text(
            'delivery_fee_unknown_hint'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Widget _row(
    ThemeData theme,
    String label,
    String value, {
    bool isBold = false,
    Color? valueColor,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: isBold
              ? theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                )
              : theme.textTheme.bodyMedium,
        ),
        Text(
          value,
          style:
              (isBold
                      ? theme.textTheme.titleMedium
                      : theme.textTheme.bodyMedium)
                  ?.copyWith(
                    fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
                    color:
                        valueColor ??
                        (isBold ? theme.colorScheme.primary : null),
                  ),
        ),
      ],
    );
  }
}

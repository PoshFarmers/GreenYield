import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../cancellation_models.dart';

// Replaced by the shared money formatter in Task 15.
String _money(num value) => 'LKR ${NumberFormat('#,##0.00').format(value)}';

/// One-line refund summary, e.g. "LKR 1,200.00 will be refunded to your wallet."
String cancellationRefundText(CancellationPreview preview) {
  if (!preview.refundable || preview.amount <= 0) {
    return 'payments_cancel_refund_none'.tr();
  }
  final amount = _money(preview.amount);
  if (preview.destination == 'card') {
    return 'payments_cancel_refund_card'.tr(
      namedArgs: {'amount': amount, 'last4': preview.cardLast4 ?? ''},
    );
  }
  return 'payments_cancel_refund_wallet'.tr(namedArgs: {'amount': amount});
}

/// Returns null if dismissed, otherwise the (possibly empty) trimmed reason.
Future<String?> showCancelOrderDialog(
  BuildContext context, {
  required String orderDisplayId,
  CancellationPreview? preview,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) =>
        _CancelOrderDialog(orderDisplayId: orderDisplayId, preview: preview),
  );
}

class _CancelOrderDialog extends StatefulWidget {
  final String orderDisplayId;
  final CancellationPreview? preview;

  const _CancelOrderDialog({
    required this.orderDisplayId,
    required this.preview,
  });

  @override
  State<_CancelOrderDialog> createState() => _CancelOrderDialogState();
}

class _CancelOrderDialogState extends State<_CancelOrderDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = widget.preview;
    final refundText = preview == null
        ? 'payments_cancel_refund_unknown'.tr()
        : cancellationRefundText(preview);

    return AlertDialog(
      title: Text('payments_cancel_title'.tr()),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'payments_cancel_body'.tr(
                namedArgs: {'order': widget.orderDisplayId},
              ),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(
                  alpha: 0.4,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.undo_outlined,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(refundText, style: theme.textTheme.bodyMedium),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _reason,
              maxLength: 200,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'payments_cancel_reason_label'.tr(),
                hintText: 'payments_cancel_reason_hint'.tr(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('payments_cancel_keep'.tr()),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: () => Navigator.of(context).pop(_reason.text.trim()),
          child: Text('payments_cancel_confirm'.tr()),
        ),
      ],
    );
  }
}

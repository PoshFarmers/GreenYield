import 'package:flutter/material.dart';

import '../../../../models/farmer_review.dart';
import '../../farmer_review_service.dart';
import 'star_rating.dart';

/// The rate-and-review form, shown either as the post-delivery popup or
/// from the farmer profile page's "Rate & review" / "Edit your review"
/// button. [existingReview] non-null switches it into edit mode (same
/// `submit_farmer_review` RPC handles both — it's an upsert on
/// `order_id`).
///
/// Returns `true` via [Navigator.pop] on a successful submit, so the
/// caller can show its own confirmation; `null`/`false` on skip/cancel.
class ReviewDialog extends StatefulWidget {
  final String orderId;
  final String farmerName;
  final FarmerReview? existingReview;

  const ReviewDialog({
    super.key,
    required this.orderId,
    required this.farmerName,
    this.existingReview,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String orderId,
    required String farmerName,
    FarmerReview? existingReview,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => ReviewDialog(
        orderId: orderId,
        farmerName: farmerName,
        existingReview: existingReview,
      ),
    );
  }

  @override
  State<ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<ReviewDialog> {
  final _service = const FarmerReviewService();
  late final _commentController = TextEditingController(
    text: widget.existingReview?.comment ?? '',
  );
  late int _rating = widget.existingReview?.rating ?? 0;
  bool _isSubmitting = false;
  String? _error;

  bool get _isEditing => widget.existingReview != null;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating < 1) {
      setState(() => _error = 'Please select a star rating.');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      await _service.submitReview(
        orderId: widget.orderId,
        rating: _rating,
        comment: _commentController.text.trim().isEmpty
            ? null
            : _commentController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = 'Could not submit your review. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: !_isSubmitting,
      child: AlertDialog(
        title: Text(_isEditing ? 'Edit your review' : 'Rate your experience'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'How was your experience with ${widget.farmerName}?',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              StarRatingInput(
                value: _rating,
                onChanged: _isSubmitting
                    ? (_) {}
                    : (v) => setState(() {
                        _rating = v;
                        _error = null;
                      }),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _commentController,
                enabled: !_isSubmitting,
                minLines: 2,
                maxLines: 4,
                maxLength: 500,
                decoration: const InputDecoration(
                  hintText: 'Share a few words (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 4),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isSubmitting
                ? null
                : () => Navigator.of(context).pop(false),
            child: Text(_isEditing ? 'Cancel' : 'Maybe later'),
          ),
          FilledButton(
            onPressed: _isSubmitting ? null : _submit,
            child: _isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_isEditing ? 'Save' : 'Submit review'),
          ),
        ],
      ),
    );
  }
}

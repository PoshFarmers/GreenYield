import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'star_rating.dart';

/// One buyer review — name, date, stars, comment. Shared by the farmer's
/// public profile (what buyers see) and the farmer's own reviews, so a
/// farmer sees their reviews exactly as buyers do.
class ReviewTile extends StatelessWidget {
  final String buyerName;
  final int rating;
  final String? comment;
  final DateTime createdAt;

  const ReviewTile({
    super.key,
    required this.buyerName,
    required this.rating,
    required this.comment,
    required this.createdAt,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = comment?.trim();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  buyerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                DateFormat.yMMMd(context.locale.toString()).format(createdAt),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          StarRatingDisplay(rating: rating.toDouble(), size: 16),
          if (text != null && text.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(text, style: theme.textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}

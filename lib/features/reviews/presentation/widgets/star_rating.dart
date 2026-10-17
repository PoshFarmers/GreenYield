import 'package:flutter/material.dart';

/// Read-only star row — whole/half/empty stars for an average (e.g. 4.6),
/// or exact stars for a single review's integer rating.
class StarRatingDisplay extends StatelessWidget {
  final double rating;
  final double size;
  final Color? color;

  const StarRatingDisplay({
    super.key,
    required this.rating,
    this.size = 18,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final starColor = color ?? Colors.amber;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final threshold = i + 1;
        IconData icon;
        if (rating >= threshold) {
          icon = Icons.star_rounded;
        } else if (rating >= threshold - 0.5) {
          icon = Icons.star_half_rounded;
        } else {
          icon = Icons.star_border_rounded;
        }
        return Icon(icon, size: size, color: starColor);
      }),
    );
  }
}

/// Interactive 1-5 star picker for submitting/editing a review.
class StarRatingInput extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  final double size;

  const StarRatingInput({
    super.key,
    required this.value,
    required this.onChanged,
    this.size = 36,
  });

  @override
  Widget build(BuildContext context) {
    final starColor = Colors.amber;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final starIndex = i + 1;
        return IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: () => onChanged(starIndex),
          icon: Icon(
            starIndex <= value ? Icons.star_rounded : Icons.star_border_rounded,
            size: size,
            color: starColor,
          ),
        );
      }),
    );
  }
}

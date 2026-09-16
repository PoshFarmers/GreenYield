import 'package:flutter/material.dart';

/// 4-step horizontal stepper used at the top of the order detail screen.
/// Steps: Placed → Packed → On The Way → Delivered
///
/// [currentStep] is 0-based (0 = Placed, 1 = Packed, 2 = On The Way,
/// 3 = Delivered). Pass -1 for cancelled to show a muted state.
class OrderStepper extends StatelessWidget {
  final int currentStep;

  const OrderStepper({super.key, required this.currentStep});

  static const _steps = ['Placed', 'Packed', 'On The Way', 'Completed'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final outline = theme.colorScheme.outlineVariant;
    final onSurface = theme.colorScheme.onSurfaceVariant;
    final isCancelled = currentStep < 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: List.generate(_steps.length, (i) {
          final isDone = !isCancelled && i < currentStep;
          final isActive = !isCancelled && i == currentStep;
          final isLast = i == _steps.length - 1;

          final stepColor = isCancelled
              ? outline
              : isDone || isActive
              ? primary
              : outline;

          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _StepCircle(
                        index: i,
                        isDone: isDone,
                        isActive: isActive,
                        isCancelled: isCancelled,
                        activeColor: primary,
                        inactiveColor: outline,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _steps[i],
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 9.5,
                          fontWeight: isActive
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: isActive
                              ? primary
                              : isDone
                              ? primary.withValues(alpha: 0.7)
                              : onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Container(
                        height: 2,
                        decoration: BoxDecoration(
                          color: isDone ? stepColor : outline,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _StepCircle extends StatelessWidget {
  final int index;
  final bool isDone;
  final bool isActive;
  final bool isCancelled;
  final Color activeColor;
  final Color inactiveColor;

  const _StepCircle({
    required this.index,
    required this.isDone,
    required this.isActive,
    required this.isCancelled,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  Widget build(BuildContext context) {
    if (isDone) {
      return Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(color: activeColor, shape: BoxShape.circle),
        child: const Icon(Icons.check, color: Colors.white, size: 16),
      );
    }

    if (isActive) {
      return Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: activeColor, width: 2.5),
        ),
        child: Center(
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: activeColor,
              shape: BoxShape.circle,
            ),
          ),
        ),
      );
    }

    // Inactive / future step.
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(color: inactiveColor, width: 1.5),
      ),
      child: Center(
        child: Text(
          '${index + 1}',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: inactiveColor,
          ),
        ),
      ),
    );
  }
}

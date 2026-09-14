import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import 'cart_nav_badge_icon.dart'; // To reuse cartItemCountProvider

class FloatingCartBadge extends ConsumerStatefulWidget {
  final String buyerProfileId;
  final GlobalKey cartIconKey;
  final VoidCallback onTap;

  const FloatingCartBadge({
    super.key,
    required this.buyerProfileId,
    required this.cartIconKey,
    required this.onTap,
  });

  @override
  ConsumerState<FloatingCartBadge> createState() => FloatingCartBadgeState();
}

class FloatingCartBadgeState extends ConsumerState<FloatingCartBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _scaleAnimation =
        TweenSequence([
          TweenSequenceItem(
            tween: Tween<double>(begin: 1.0, end: 1.2),
            weight: 1,
          ),
          TweenSequenceItem(
            tween: Tween<double>(begin: 1.2, end: 1.0),
            weight: 1,
          ),
        ]).animate(
          CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
        );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  /// Manually trigger the pulse/shake effect when the flying animation arrives.
  void pulse() {
    _pulseController.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    final countAsync = ref.watch(cartItemCountProvider(widget.buyerProfileId));
    final count = countAsync.asData?.value ?? 0.0;
    final displayCount = count.toInt();

    final theme = Theme.of(context);

    return ScaleTransition(
      scale: _scaleAnimation,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          key: widget.cartIconKey,
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              const Icon(
                Icons.shopping_cart_outlined,
                color: AppColors.deepForestGreen,
                size: 26,
              ),
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    border: Border.all(
                      color: theme.colorScheme.surface,
                      width: 2,
                    ),
                    shape: displayCount > 9
                        ? BoxShape.rectangle
                        : BoxShape.circle,
                    borderRadius: displayCount > 9
                        ? BorderRadius.circular(10)
                        : null,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 22,
                    minHeight: 22,
                  ),
                  child: Center(
                    child: Text(
                      displayCount > 99 ? '99+' : '$displayCount',
                      style: const TextStyle(
                        color: AppColors.onPrimary,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        height: 1.0,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

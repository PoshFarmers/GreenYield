import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../cart_service.dart';

/// Provides the cart item count stream.
final cartItemCountProvider = StreamProvider.family<double, String>((
  ref,
  buyerId,
) {
  return const CartService().watchItemCount(buyerId);
});

class CartNavBadgeIcon extends ConsumerWidget {
  final String buyerProfileId;

  const CartNavBadgeIcon({super.key, required this.buyerProfileId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countAsync = ref.watch(cartItemCountProvider(buyerProfileId));
    final count = countAsync.asData?.value ?? 0.0;
    final displayCount = count.toInt();

    return Badge(
      isLabelVisible: displayCount > 0,
      label: Text(displayCount > 99 ? '99+' : '$displayCount'),
      backgroundColor: AppColors.warnAmber,
      textColor: AppColors.deepForestGreen,
      child: const Icon(Icons.shopping_cart_outlined),
    );
  }
}

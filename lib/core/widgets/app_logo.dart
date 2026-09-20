import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The GreenYield logo — the one place the asset path lives. Every
/// screen that shows the brand mark (header, login, splash, onboarding)
/// goes through this instead of `Image.asset` directly, so swapping the
/// artwork later is a one-file change.
///
/// The artwork is a self-contained rounded green tile, so it reads on
/// both light and dark backgrounds without a separate dark variant.
class AppLogo extends StatelessWidget {
  static const assetPath = 'assets/images/logo.png';

  final double size;

  /// Optional "GreenYield" wordmark to the right of the mark.
  final bool showName;
  final TextStyle? nameStyle;

  const AppLogo({
    super.key,
    this.size = 32,
    this.showName = false,
    this.nameStyle,
  });

  @override
  Widget build(BuildContext context) {
    final mark = Image.asset(
      assetPath,
      width: size,
      height: size,
      // Decode at display size (not the full 585px source) — this is
      // drawn on nearly every screen via the header.
      cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
      filterQuality: FilterQuality.medium,
      semanticLabel: showName ? null : 'app_name'.tr(),
    );
    if (!showName) return mark;

    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        SizedBox(width: size * 0.28),
        Text(
          'app_name'.tr(),
          style:
              nameStyle ??
              GoogleFonts.outfit(
                textStyle: theme.textTheme.titleLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
        ),
      ],
    );
  }
}

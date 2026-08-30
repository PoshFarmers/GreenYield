import 'package:flutter/material.dart';

/// Brand seed colors
class AppColors {
  AppColors._();

  static const Color seed = Color(0xFF2E7D32); // GreenYield green

  // Fixed brand palette (independent of light/dark ColorScheme), used by
  // components — like notifications — that need a consistent look across
  // both themes rather than adapting to the seeded scheme.
  static const Color deepForestGreen = Color(0xFF1B4D3E);
  static const Color freshLeafGreen = Color(0xFF4CAF50);
  static const Color warnAmber = Color(0xFFFFC107);
  static const Color cream = Color(0xFFF9FBF8);
  static const Color mutedGray = Color(0xFF757575);
}

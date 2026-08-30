import 'package:flutter/material.dart';

/// Single source of truth for every color used in the app.
/// Don't reference these directly from widgets — go through
/// `Theme.of(context).colorScheme` (see app_theme.dart). Keeping the
/// raw values here just makes them easy to tweak in one place.
class AppColors {
  AppColors._();

  // Shared -------------------------------------------------------------
  static const Color primary = Color(0xFF277433);
  static const Color onPrimary = Colors.white;
  static const Color error = Color(0xFFB3261E);

  // Light theme ----------------------------------------------------------
  static const Color lightBackground = Color(0xFFFAFAF5);
  static const Color lightSurface = Colors.white;
  static const Color lightBorder = Color(0xFFE0E0DA);
  static const Color lightTextPrimary = Color(0xFF1B1B18);
  static const Color lightTextSecondary = Color(0xFF6B6B63);
  static const Color lightPrimaryTint = Color(0xFFE3EFE3);

  // Dark theme -------------------------------------------------------------
  static const Color darkBackground = Color(0xFF121212);
  static const Color darkSurface = Color(0xFF1E1E1E);
  static const Color darkBorder = Color(0xFF3A3A3A);
  static const Color darkTextPrimary = Color(0xFFE8E8E8);
  static const Color darkTextSecondary = Color(0xFF9E9E9E);
  static const Color darkPrimaryTint = Color(0xFF1A3A1A);

  // `primary` (#277433) on top of `darkBackground`/`darkSurface` sits at
  // roughly a 3.2:1 contrast ratio — good enough for a filled button, but
  // too low if it's used as text or an icon on its own (links, the "eco"
  // logo mark, etc). `darkPrimary` is a lifted version of the brand green
  // used anywhere green needs to be *read*, not just filled, in dark mode.
  static const Color darkPrimary = Color(0xFF4CAF50);
  static const Color darkError = Color(0xFFE6867E);
}

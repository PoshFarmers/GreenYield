import 'package:flutter/material.dart';

/// Minimal, dependency-free stand-in for the multicolor Google "G". Swap
/// for a real asset (e.g. `assets/icons/google.png`) whenever one is added.
class GoogleGlyph extends StatelessWidget {
  const GoogleGlyph({super.key});

  @override
  Widget build(BuildContext context) {
    return const Text(
      'G',
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Color(0xFF4285F4),
      ),
    );
  }
}

import 'package:flutter/material.dart';

/// Placeholder for a nav-bar tab whose feature hasn't been merged yet
/// (e.g. Harvest, Cart, Deliveries, Chat). Swap this out for the real
/// screen as each Epic's branch lands — the nav shell itself doesn't
/// need to change.
class ComingSoonScreen extends StatelessWidget {
  final String title;

  const ComingSoonScreen({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Text(
          '$title — coming soon',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    );
  }
}

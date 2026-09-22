import 'package:flutter/material.dart';

/// Re-renders the whole app (including pushed routes) when [locale]
/// changes.
///
/// easy_localization only rebuilds widgets that read `context.locale`;
/// almost every screen here uses the context-free `'key'.tr()`, so
/// without this, switching language left existing screens showing the
/// old language until something else happened to rebuild them. Wired in
/// via `MaterialApp.builder`, so it sits above the Navigator.
class LocaleRebuildScope extends StatefulWidget {
  final Locale locale;
  final Widget child;

  const LocaleRebuildScope({
    super.key,
    required this.locale,
    required this.child,
  });

  @override
  State<LocaleRebuildScope> createState() => _LocaleRebuildScopeState();
}

class _LocaleRebuildScopeState extends State<LocaleRebuildScope> {
  @override
  void didUpdateWidget(LocaleRebuildScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.locale == widget.locale) return;
    // After this frame rather than mid-build, so marking every
    // descendant dirty is always allowed. The one-frame lag isn't
    // visible.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      void rebuild(Element element) {
        element.markNeedsBuild();
        element.visitChildren(rebuild);
      }

      (context as Element).visitChildren(rebuild);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

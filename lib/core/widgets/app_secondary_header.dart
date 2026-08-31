import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Reusable "sub-page" header: back arrow + centered title + optional
/// help icon. This is the shape most non-nav-shell screens want (edit
/// forms, onboarding steps, detail screens, ...) — as opposed to
/// [AppHeader], which is specifically the branded header for the main
/// nav-shell screens.
///
/// [showBackButton] defaults to true (the common case for a pushed
/// screen); pass false for a screen reached through state-driven
/// navigation with nothing to pop back to (see the `AuthGate` flow
/// notes in CLAUDE.md — onboarding steps typically fall in this
/// bucket). [helpText] is optional; the help icon only appears when
/// it's provided.
class AppSecondaryHeader extends StatelessWidget
    implements PreferredSizeWidget {
  final String title;
  final bool showBackButton;

  /// Overrides the default `Navigator.maybePop()` — e.g. a multi-step
  /// wizard where "back" should go to the previous step instead of
  /// popping the route until the last step.
  final VoidCallback? onBackPressed;
  final String? helpText;
  final List<Widget>? actions;

  /// Extra content below the title bar (e.g. a step progress indicator).
  final PreferredSizeWidget? bottom;

  const AppSecondaryHeader({
    super.key,
    required this.title,
    this.showBackButton = true,
    this.onBackPressed,
    this.helpText,
    this.actions,
    this.bottom,
  });

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    return AppBar(
      centerTitle: true,
      automaticallyImplyLeading: showBackButton,
      leading: showBackButton
          ? BackButton(
              onPressed:
                  onBackPressed ?? () => Navigator.of(context).maybePop(),
            )
          : null,
      title: Text(title, style: Theme.of(context).textTheme.titleLarge),
      bottom: bottom,
      actions: [
        if (helpText != null)
          IconButton(
            tooltip: 'help'.tr(),
            icon: const Icon(Icons.help_outline),
            onPressed: () => showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: Text('help'.tr()),
                content: Text(helpText!),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('ok'.tr()),
                  ),
                ],
              ),
            ),
          ),
        ...?actions,
      ],
    );
  }
}

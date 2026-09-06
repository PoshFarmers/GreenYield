import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One tab of a role's nav shell.
class NavTab {
  final String label;
  final IconData icon;
  final WidgetBuilder builder;

  /// Optional override for the destination icon — used by the Chat tab
  /// to show a live yellow unread-thread badge instead of a plain
  /// [Icon] (see `ChatNavBadgeIcon`). Falls back to `Icon(icon)` when
  /// omitted.
  final WidgetBuilder? iconBuilder;

  const NavTab({
    required this.label,
    required this.icon,
    required this.builder,
    this.iconBuilder,
  });
}

/// The shell's selected tab index.
///
/// Held in a provider rather than local State so a pushed route can send
/// the user to a different tab — e.g. "Message Farmer" on the listing
/// detail screen popping back to the shell and landing on Chat.
class NavShellIndex extends Notifier<int> {
  @override
  int build() => 0;

  void select(int index) => state = index;
}

final navShellIndexProvider = NotifierProvider<NavShellIndex, int>(
  NavShellIndex.new,
);

/// A single reusable bottom-nav scaffold. Each role (Farmer/Buyer/Driver)
/// just supplies its own list of [NavTab]s — see
/// `core/roles/role_nav_shell_registry.dart`.
class AppNavShell extends ConsumerStatefulWidget {
  final List<NavTab> tabs;
  final int initialIndex;

  const AppNavShell({super.key, required this.tabs, this.initialIndex = 0});

  @override
  ConsumerState<AppNavShell> createState() => _AppNavShellState();
}

class _AppNavShellState extends ConsumerState<AppNavShell> {
  @override
  void initState() {
    super.initState();
    if (widget.initialIndex != 0) {
      // Provider writes aren't allowed during build/init, so defer one frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(navShellIndexProvider.notifier).select(widget.initialIndex);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Clamped so a stale index from a previous role's shell (which may
    // have had more tabs) can't crash IndexedStack.
    final index = ref
        .watch(navShellIndexProvider)
        .clamp(0, widget.tabs.length - 1);

    return Scaffold(
      body: IndexedStack(
        index: index,
        children: [
          for (final tab in widget.tabs) Builder(builder: tab.builder),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) =>
            ref.read(navShellIndexProvider.notifier).select(i),
        destinations: [
          for (final tab in widget.tabs)
            NavigationDestination(
              icon: tab.iconBuilder != null
                  ? Builder(builder: tab.iconBuilder!)
                  : Icon(tab.icon),
              label: tab.label,
            ),
        ],
      ),
    );
  }
}

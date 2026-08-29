import 'package:flutter/material.dart';

/// One tab of a role's nav shell.
class NavTab {
  final String label;
  final IconData icon;
  final WidgetBuilder builder;

  const NavTab({
    required this.label,
    required this.icon,
    required this.builder,
  });
}

/// A single reusable bottom-nav scaffold. Each role (Farmer/Buyer/Driver)
/// just supplies its own list of [NavTab]s — see
/// `core/roles/role_nav_shell_registry.dart`.
class AppNavShell extends StatefulWidget {
  final List<NavTab> tabs;
  final int initialIndex;

  const AppNavShell({super.key, required this.tabs, this.initialIndex = 0});

  @override
  State<AppNavShell> createState() => _AppNavShellState();
}

class _AppNavShellState extends State<AppNavShell> {
  late int _index = widget.initialIndex;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          for (final tab in widget.tabs) Builder(builder: tab.builder),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final tab in widget.tabs)
            NavigationDestination(icon: Icon(tab.icon), label: tab.label),
        ],
      ),
    );
  }
}

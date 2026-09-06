/// The application shell: theme and responsive navigation.
library;

import 'package:flutter/material.dart';

import 'features/assets/assets_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/tracker_controller.dart';
import 'features/transactions/transactions_screen.dart';

class FinanceTrackerApp extends StatelessWidget {
  const FinanceTrackerApp({super.key, required this.controller});

  final TrackerController controller;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Finance Tracker',
    theme: ThemeData(colorSchemeSeed: Colors.teal, brightness: Brightness.light),
    darkTheme: ThemeData(
      colorSchemeSeed: Colors.teal,
      brightness: Brightness.dark,
    ),
    home: HomeShell(controller: controller),
  );
}

class _Destination {
  const _Destination(this.label, this.icon, this.builder);

  final String label;
  final IconData icon;
  final Widget Function(TrackerController) builder;
}

final List<_Destination> _destinations = [
  _Destination(
    'Dashboard',
    Icons.dashboard,
    (controller) => DashboardScreen(controller: controller),
  ),
  _Destination(
    'Transactions',
    Icons.receipt_long,
    (controller) => TransactionsScreen(controller: controller),
  ),
  _Destination(
    'Assets',
    Icons.show_chart,
    (controller) => AssetsScreen(controller: controller),
  ),
];

/// Compact windows navigate with a `NavigationBar`, wider ones with a
/// `NavigationRail`, at the 600 logical pixel breakpoint from `docs/ui.md`.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.controller});

  final TrackerController controller;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  void _select(int index) => setState(() => _index = index);

  @override
  Widget build(BuildContext context) {
    final destination = _destinations[_index];
    final body = SafeArea(child: destination.builder(widget.controller));

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 600) {
          return Scaffold(
            appBar: AppBar(title: Text(destination.label)),
            body: body,
            bottomNavigationBar: NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: _select,
              destinations: [
                for (final item in _destinations)
                  NavigationDestination(
                    icon: Icon(item.icon),
                    label: item.label,
                  ),
              ],
            ),
          );
        }
        return Scaffold(
          appBar: AppBar(title: Text(destination.label)),
          body: Row(
            children: [
              NavigationRail(
                selectedIndex: _index,
                onDestinationSelected: _select,
                labelType: NavigationRailLabelType.all,
                destinations: [
                  for (final item in _destinations)
                    NavigationRailDestination(
                      icon: Icon(item.icon),
                      label: Text(item.label),
                    ),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: body),
            ],
          ),
        );
      },
    );
  }
}

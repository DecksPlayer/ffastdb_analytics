import 'package:flutter/material.dart';
import 'package:ffastdb/ffastdb.dart';

import 'db_service.dart';
import 'pages/balance_page.dart';
import 'pages/results_page.dart';
import 'pages/pivot_page.dart';
import 'pages/cashflow_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await DbService.init();
  runApp(AnalyticsApp(db: db));
}

class AnalyticsApp extends StatelessWidget {
  const AnalyticsApp({super.key, required this.db});
  final FastDB db;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Libro Contable — ffastdb_analytics',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A6B4A),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: DashboardShell(db: db),
    );
  }
}

// ─── Shell with bottom navigation ────────────────────────────────────────────

class DashboardShell extends StatefulWidget {
  const DashboardShell({super.key, required this.db});
  final FastDB db;

  @override
  State<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends State<DashboardShell> {
  int _index = 0;

  late final List<_TabDef> _tabs = [
    _TabDef(
      label: 'Balance',
      icon: Icons.account_balance_outlined,
      page: BalancePage(db: widget.db),
    ),
    _TabDef(
      label: 'Resultados',
      icon: Icons.bar_chart_outlined,
      page: ResultsPage(db: widget.db),
    ),
    _TabDef(
      label: 'Pivot',
      icon: Icons.table_chart_outlined,
      page: PivotPage(db: widget.db),
    ),
    _TabDef(
      label: 'Flujo',
      icon: Icons.show_chart_outlined,
      page: CashFlowPage(db: widget.db),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: _tabs.map((t) => t.page).toList(),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: _tabs
            .map((t) => NavigationDestination(
                  icon: Icon(t.icon),
                  label: t.label,
                ))
            .toList(),
      ),
    );
  }
}

class _TabDef {
  final String label;
  final IconData icon;
  final Widget page;
  const _TabDef({required this.label, required this.icon, required this.page});
}

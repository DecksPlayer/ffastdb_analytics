import 'package:flutter/material.dart';
import 'package:ffastdb/ffastdb.dart';
import 'package:ffastdb_analytics/ffastdb_analytics.dart';

/// Pivot page — gastos por categoría × trimestre (PivotAgg.sum).
///
/// Renders the cross-tabulation as a scrollable data table.
/// Uses a [FutureBuilder] — refresh button re-runs the pivot.
class PivotPage extends StatefulWidget {
  const PivotPage({super.key, required this.db});
  final FastDB db;

  @override
  State<PivotPage> createState() => _PivotPageState();
}

class _PivotPageState extends State<PivotPage> {
  late Future<PivotTable> _future;

  @override
  void initState() {
    super.initState();
    _future = _runPivot();
  }

  Future<PivotTable> _runPivot() => widget.db.analytics
      .where((q) => q.where('tipo').equals('GASTO').findIds())
      .pivot(
        rowField: 'categoria',
        colField: 'trimestre',
        valueField: 'monto',
        aggregation: PivotAgg.sum,
      );

  void _refresh() => setState(() => _future = _runPivot());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pivot — Gastos por categoría × trimestre'),
        centerTitle: false,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
        ],
      ),
      body: FutureBuilder<PivotTable>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          final table = snap.data!;
          return _PivotTableView(table: table);
        },
      ),
    );
  }
}

class _PivotTableView extends StatelessWidget {
  const _PivotTableView({required this.table});
  final PivotTable table;

  @override
  Widget build(BuildContext context) {
    final cols = table.columnKeys.cast<String>()..sort();
    final rows = table.rows.entries.toList()
      ..sort((a, b) => (a.key as String).compareTo(b.key as String));

    // Find max value for heat-map coloring
    double maxVal = 0;
    for (final row in rows) {
      for (final col in cols) {
        final v = (row.value[col] as num?)?.toDouble() ?? 0;
        if (v > maxVal) maxVal = v;
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Legend
          Row(
            children: [
              Container(
                  width: 14,
                  height: 14,
                  color: const Color(0xFFB03A2E).withAlpha(30)),
              const SizedBox(width: 6),
              const Text('Bajo', style: TextStyle(fontSize: 12)),
              const SizedBox(width: 16),
              Container(
                  width: 14,
                  height: 14,
                  color: const Color(0xFFB03A2E).withAlpha(200)),
              const SizedBox(width: 6),
              const Text('Alto', style: TextStyle(fontSize: 12)),
            ],
          ),
          const SizedBox(height: 16),

          // Table
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              border: TableBorder.all(
                  color: Colors.grey.shade300, borderRadius: BorderRadius.circular(4)),
              children: [
                // Header
                TableRow(
                  decoration: BoxDecoration(color: Colors.grey.shade100),
                  children: [
                    _HeaderCell('Categoría', minWidth: 160),
                    for (final col in cols) _HeaderCell(col),
                    _HeaderCell('Total'),
                  ],
                ),
                // Data rows
                for (final row in rows)
                  TableRow(
                    children: [
                      _LabelCell(row.key as String),
                      for (final col in cols)
                        _ValueCell(
                          value: (row.value[col] as num?)?.toDouble() ?? 0,
                          maxVal: maxVal,
                        ),
                      _TotalCell(
                        cols.fold(
                            0.0,
                            (s, c) =>
                                s + ((row.value[c] as num?)?.toDouble() ?? 0)),
                      ),
                    ],
                  ),
                // Column totals row
                TableRow(
                  decoration: BoxDecoration(color: Colors.grey.shade100),
                  children: [
                    _HeaderCell('Total'),
                    for (final col in cols)
                      _TotalCell(rows.fold(
                          0.0,
                          (s, r) =>
                              s + ((r.value[col] as num?)?.toDouble() ?? 0))),
                    _TotalCell(rows.fold(
                        0.0,
                        (s, r) => s +
                            cols.fold(
                                0.0,
                                (cs, c) =>
                                    cs +
                                    ((r.value[c] as num?)?.toDouble() ?? 0)))),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.text, {this.minWidth = 80});
  final String text;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: minWidth),
        child: Text(text,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            textAlign: TextAlign.center),
      ),
    );
  }
}

class _LabelCell extends StatelessWidget {
  const _LabelCell(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Text(text, style: const TextStyle(fontSize: 12)),
      );
}

class _ValueCell extends StatelessWidget {
  const _ValueCell({required this.value, required this.maxVal});
  final double value;
  final double maxVal;

  @override
  Widget build(BuildContext context) {
    final ratio = maxVal > 0 ? (value / maxVal).clamp(0.0, 1.0) : 0.0;
    final bg = Color.lerp(
      const Color(0xFFB03A2E).withAlpha(20),
      const Color(0xFFB03A2E).withAlpha(200),
      ratio,
    )!;

    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Text(
        value > 0 ? _fmt(value) : '—',
        textAlign: TextAlign.right,
        style: const TextStyle(fontSize: 12, fontFeatures: []),
      ),
    );
  }
}

class _TotalCell extends StatelessWidget {
  const _TotalCell(this.value);
  final double value;

  @override
  Widget build(BuildContext context) => Container(
        color: Colors.grey.shade200,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Text(
          _fmt(value),
          textAlign: TextAlign.right,
          style:
              const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
      );
}

String _fmt(double n) =>
    '\$${n.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},')}';

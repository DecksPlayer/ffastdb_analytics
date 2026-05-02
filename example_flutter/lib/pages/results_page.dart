import 'package:flutter/material.dart';
import 'package:ffastdb/ffastdb.dart';
import 'package:ffastdb_analytics/ffastdb_analytics.dart';

/// Estado de Resultados — ingresos vs gastos por trimestre.
///
/// Computes revenue and expenses in parallel using two filtered groupBys,
/// then displays a visual comparison bar per quarter.
class ResultsPage extends StatefulWidget {
  const ResultsPage({super.key, required this.db});
  final FastDB db;

  @override
  State<ResultsPage> createState() => _ResultsPageState();
}

class _ResultsPageState extends State<ResultsPage> {



  Stream<({List<_QuarterRow> rows, double? p90, double? sigma})> _resultsStream() async* {
    // Yield initial data
    yield await _fetchData();

    // Re-yield whenever 'monto' (the main analytical field) changes
    await for (final _ in widget.db.watch('monto')) {
      yield await _fetchData();
    }
  }

  Future<({List<_QuarterRow> rows, double? p90, double? sigma})> _fetchData() async {
    final results = await Future.wait([
      db.analytics
          .where((q) => q.where('tipo').equals('INGRESO').findIds())
          .groupBy('trimestre', {'total': aggSum('monto')}),
      db.analytics
          .where((q) => q.where('tipo').equals('GASTO').findIds())
          .groupBy('trimestre', {'total': aggSum('monto')}),
      db.analytics
          .where((q) => q.where('tipo').equals('GASTO').findIds())
          .percentile('monto', 0.90)
          .then((v) => [v]),
      db.analytics
          .where((q) => q.where('tipo').equals('GASTO').findIds())
          .stddev('monto')
          .then((v) => [v]),
    ]);

    final ingMap = {
      for (final g in results[0] as List<GroupByResult>)
        g.key as String: (g.aggregations['total'] as num).toDouble()
    };
    final gasMap = {
      for (final g in results[1] as List<GroupByResult>)
        g.key as String: (g.aggregations['total'] as num).toDouble()
    };

    final quarters = ['T1', 'T2', 'T3', 'T4'];
    final rows = quarters.map((t) {
      final ing = ingMap[t] ?? 0;
      final gas = gasMap[t] ?? 0;
      return _QuarterRow(trimestre: t, ingresos: ing, gastos: gas);
    }).toList();

    return (
      rows: rows,
      p90: (results[2] as List<double?>).first,
      sigma: (results[3] as List<double?>).first,
    );
  }

  FastDB get db => widget.db;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Estado de Resultados'),
        centerTitle: false,
      ),
      body: StreamBuilder<({List<_QuarterRow> rows, double? p90, double? sigma})>(
        stream: _resultsStream(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snap.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const _SectionHeader('Ingresos vs Gastos por trimestre'),
              const SizedBox(height: 12),
              ...(data.rows.map((r) => _QuarterCard(row: r))),
              const SizedBox(height: 24),
              const _SectionHeader('Totales del ejercicio'),
              const SizedBox(height: 12),
              _SummaryRow(rows: data.rows),
              const SizedBox(height: 24),
              const _SectionHeader('Alertas estadísticas — Gastos'),
              const SizedBox(height: 12),
              _StatCard(p90: data.p90, sigma: data.sigma),
            ],
          );
        },
      ),
    );
  }
}

// ─── Data model ───────────────────────────────────────────────────────────────

class _QuarterRow {
  final String trimestre;
  final double ingresos;
  final double gastos;
  double get utilidad => ingresos - gastos;
  bool get profitable => utilidad >= 0;
  const _QuarterRow(
      {required this.trimestre,
      required this.ingresos,
      required this.gastos});
}

// ─── Widgets ─────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(text,
      style: Theme.of(context)
          .textTheme
          .titleSmall
          ?.copyWith(fontWeight: FontWeight.bold));
}

class _QuarterCard extends StatelessWidget {
  const _QuarterCard({required this.row});
  final _QuarterRow row;

  @override
  Widget build(BuildContext context) {
    final max = row.ingresos > row.gastos ? row.ingresos : row.gastos;
    final incomeRatio = max > 0 ? row.ingresos / max : 0.0;
    final expenseRatio = max > 0 ? row.gastos / max : 0.0;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(row.trimestre,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: row.profitable
                        ? const Color(0xFF1A6B4A)
                        : const Color(0xFFB03A2E),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${row.profitable ? '+' : ''}${_fmt(row.utilidad)}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _Bar(label: 'Ingresos', value: row.ingresos, ratio: incomeRatio,
                color: const Color(0xFF1A6B4A)),
            const SizedBox(height: 4),
            _Bar(label: 'Gastos', value: row.gastos, ratio: expenseRatio,
                color: const Color(0xFFB03A2E)),
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar(
      {required this.label,
      required this.value,
      required this.ratio,
      required this.color});
  final String label;
  final double value;
  final double ratio;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
            width: 64,
            child: Text(label,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700))),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio.clamp(0.0, 1.0),
              backgroundColor: color.withAlpha(30),
              valueColor: AlwaysStoppedAnimation(color),
              minHeight: 14,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(_fmt(value),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.rows});
  final List<_QuarterRow> rows;

  @override
  Widget build(BuildContext context) {
    final totalIng = rows.fold(0.0, (s, r) => s + r.ingresos);
    final totalGas = rows.fold(0.0, (s, r) => s + r.gastos);
    final utilidad = totalIng - totalGas;

    return Row(
      children: [
        _SumCard('Ingresos anuales', _fmt(totalIng),
            const Color(0xFF1A6B4A)),
        const SizedBox(width: 8),
        _SumCard('Gastos anuales', _fmt(totalGas),
            const Color(0xFFB03A2E)),
        const SizedBox(width: 8),
        _SumCard(
            'Utilidad neta',
            _fmt(utilidad),
            utilidad >= 0
                ? const Color(0xFF1A6B4A)
                : const Color(0xFFB03A2E)),
      ],
    );
  }
}

class _SumCard extends StatelessWidget {
  const _SumCard(this.label, this.value, this.color);
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          border: Border.all(color: color.withAlpha(80)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: color)),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({this.p90, this.sigma});
  final double? p90;
  final double? sigma;

  @override
  Widget build(BuildContext context) {
    final threshold = (p90 ?? 0) + (sigma ?? 0);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StatRow('Percentil 90', p90),
            _StatRow('Desviación estándar (σ)', sigma),
            const Divider(height: 20),
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: Colors.orange, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Umbral de alerta (p90 + σ): ${_fmt(threshold)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow(this.label, this.value);
  final String label;
  final double? value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade700)),
          Text(value != null ? _fmt(value!) : '—',
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

String _fmt(double n) =>
    '\$${n.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},')}';

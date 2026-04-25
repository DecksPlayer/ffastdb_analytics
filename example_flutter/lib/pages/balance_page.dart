import 'package:flutter/material.dart';
import 'package:ffastdb/ffastdb.dart';
import 'package:ffastdb_analytics/ffastdb_analytics.dart';

/// Balance page — live groupBy per account type using [watchGroupBy].
///
/// Reacts to inserts/updates automatically. Shows a summary card per
/// tipo with total, transaction count, average and max amounts.
/// A FAB lets the user add a random INGRESO to see the live update.
class BalancePage extends StatelessWidget {
  const BalancePage({super.key, required this.db});
  final FastDB db;

  static const _typeColors = {
    'INGRESO':    Color(0xFF1A6B4A),
    'GASTO':      Color(0xFFB03A2E),
    'ACTIVO':     Color(0xFF1A5276),
    'PASIVO':     Color(0xFF784212),
    'PATRIMONIO': Color(0xFF6C3483),
  };

  static const _typeIcons = {
    'INGRESO':    Icons.trending_up,
    'GASTO':      Icons.trending_down,
    'ACTIVO':     Icons.account_balance_wallet_outlined,
    'PASIVO':     Icons.credit_card_outlined,
    'PATRIMONIO': Icons.savings_outlined,
  };

  @override
  Widget build(BuildContext context) {
    // watchGroupBy re-runs groupBy whenever 'tipo' index changes
    final stream = db.analytics.all.watchGroupBy(
      'tipo',
      'tipo',
      {
        'total':   aggSum('monto'),
        'n':       aggCount(),
        'avg':     aggAvg('monto'),
        'max':     aggMax('monto'),
      },
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Balance por tipo de cuenta'),
        centerTitle: false,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addRandomIngreso(),
        icon: const Icon(Icons.add),
        label: const Text('Agregar ingreso'),
      ),
      body: StreamBuilder<List<GroupByResult>>(
        stream: stream,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final groups = snap.data!
            ..sort((a, b) => (a.key as String).compareTo(b.key as String));

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: groups.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final g = groups[i];
              final tipo = g.key as String;
              final color = _typeColors[tipo] ?? Colors.grey;
              final icon  = _typeIcons[tipo]  ?? Icons.circle;
              final total = g.aggregations['total'] as num;
              final avg   = g.aggregations['avg']   as num;
              final max   = g.aggregations['max']   as num;

              return Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header strip
                    Container(
                      color: color,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      child: Row(
                        children: [
                          Icon(icon, color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            tipo,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const Spacer(),
                          Chip(
                            backgroundColor: Colors.white24,
                            label: Text(
                              '${g.count} movimientos',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 12),
                            ),
                            padding: EdgeInsets.zero,
                          ),
                        ],
                      ),
                    ),
                    // Metrics
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          _Metric(
                              label: 'Total',
                              value: _fmt(total),
                              color: color),
                          _Metric(label: 'Promedio', value: _fmt(avg)),
                          _Metric(label: 'Máximo', value: _fmt(max)),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _addRandomIngreso() async {
    final now = DateTime.now();
    final mes  = (now.millisecondsSinceEpoch % 12) + 1;
    final trimestres = {
      1:'T1',2:'T1',3:'T1',4:'T2',5:'T2',6:'T2',
      7:'T3',8:'T3',9:'T3',10:'T4',11:'T4',12:'T4'
    };
    await db.insert({
      'tipo':      'INGRESO',
      'cuenta':    'Venta especial',
      'categoria': 'Ventas',
      'mes':       mes,
      'trimestre': trimestres[mes],
      'monto':     (now.millisecondsSinceEpoch % 5000) + 1000.0,
      'pagado':    true,
    });
  }

  static String _fmt(num n) =>
      '\$${n.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},')}';
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color ?? Colors.black87,
              )),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:ffastdb/ffastdb.dart';
import 'package:ffastdb_analytics/ffastdb_analytics.dart';

/// Balance page — live groupBy per account type using [watchGroupBy].
class BalancePage extends StatefulWidget {
  const BalancePage({super.key, required this.db});
  final FastDB db;

  @override
  State<BalancePage> createState() => _BalancePageState();

  static const _typeColors = {
    'INGRESO': Color(0xFF1A6B4A),
    'GASTO': Color(0xFFB03A2E),
    'ACTIVO': Color(0xFF1A5276),
    'PASIVO': Color(0xFF784212),
    'PATRIMONIO': Color(0xFF6C3483),
  };

  static const _typeIcons = {
    'INGRESO': Icons.trending_up,
    'GASTO': Icons.trending_down,
    'ACTIVO': Icons.account_balance_wallet_outlined,
    'PASIVO': Icons.credit_card_outlined,
    'PATRIMONIO': Icons.savings_outlined,
  };
}

class _BalancePageState extends State<BalancePage> {
  late Stream<List<GroupByResult>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = widget.db.analytics.all.watchGroupBy('tipo', 'tipo', {
      'total': aggSum('monto'),
      'n': aggCount(),
      'avg': aggAvg('monto'),
      'max': aggMax('monto'),
    });
  }

  PreferredSizeWidget _appBar(BuildContext context) {
    return AppBar(
      title: const Text('Balance por tipo de cuenta'),
      centerTitle: false,
      actions: [
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Limpiar base de datos',
          onPressed: () => _confirmClear(context),
        ),
      ],
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Limpiar datos?'),
        content: const Text('Se eliminarán todos los movimientos registrados.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCELAR'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('LIMPIAR'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final ids = await widget.db.query().findIds();
      for (final id in ids) {
        await widget.db.delete(id);
      }
      await widget.db.compact();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Base de datos vaciada')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _appBar(context),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo movimiento'),
      ),
      body: StreamBuilder<List<GroupByResult>>(
        stream: _stream,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final groups = snap.data!
            ..sort((a, b) => (a.key as String).compareTo(b.key as String));

          if (groups.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.account_balance_outlined,
                    size: 64,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No hay movimientos',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: groups.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final g = groups[i];
              final tipo = g.key as String;
              final color = BalancePage._typeColors[tipo] ?? Colors.grey;
              final icon = BalancePage._typeIcons[tipo] ?? Icons.circle;
              final total = g.aggregations['total'] as num;
              final avg = g.aggregations['avg'] as num;
              final max = g.aggregations['max'] as num;

              return Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      color: color,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
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
                              '${g.count} mov.',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                              ),
                            ),
                            padding: EdgeInsets.zero,
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          _Metric(
                            label: 'Total',
                            value: _fmt(total),
                            color: color,
                          ),
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

  Future<void> _showAddDialog(BuildContext context) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const _AddEntryDialog(),
    );

    if (result != null) {
      try {
        final id = await widget.db.insert(result);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Movimiento #$id registrado'),
              backgroundColor: BalancePage._typeColors[result['tipo']] ??
                  const Color(0xFF1A6B4A),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
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
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color ?? Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

class _AddEntryDialog extends StatefulWidget {
  const _AddEntryDialog();
  @override
  State<_AddEntryDialog> createState() => _AddEntryDialogState();
}

class _AddEntryDialogState extends State<_AddEntryDialog> {
  String _tipo = 'INGRESO';
  final _montoCtrl = TextEditingController();
  final _catCtrl = TextEditingController(text: 'General');
  final _cuentaCtrl = TextEditingController(text: 'Nueva Cuenta');

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nuevo movimiento'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: _tipo,
              decoration: const InputDecoration(labelText: 'Tipo'),
              items: BalancePage._typeColors.keys
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) => setState(() => _tipo = v!),
            ),
            TextField(
              controller: _catCtrl,
              decoration: const InputDecoration(labelText: 'Categoría'),
            ),
            TextField(
              controller: _cuentaCtrl,
              decoration: const InputDecoration(labelText: 'Cuenta'),
            ),
            TextField(
              controller: _montoCtrl,
              decoration: const InputDecoration(
                labelText: 'Monto',
                prefixText: r'$',
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CANCELAR'),
        ),
        ElevatedButton(
          onPressed: () {
            final now = DateTime.now();
            final months = [
              'Ene',
              'Feb',
              'Mar',
              'Abr',
              'May',
              'Jun',
              'Jul',
              'Ago',
              'Sep',
              'Oct',
              'Nov',
              'Dic',
            ];
            Navigator.pop(context, {
              'tipo': _tipo,
              'categoria': _catCtrl.text,
              'cuenta': _cuentaCtrl.text,
              'monto': double.tryParse(_montoCtrl.text) ?? 0.0,
              'fecha': now.toIso8601String(),
              'mes': now.month,
              'trimestre': 'T${((now.month - 1) ~/ 3) + 1}',
            });
          },
          child: const Text('GUARDAR'),
        ),
      ],
    );
  }
}

// Ejemplo: Libro Contable — ffastdb_analytics
//
// Modela asientos contables de una empresa durante un ejercicio fiscal.
// Cada documento representa una línea de movimiento con:
//   tipo     → INGRESO | GASTO | ACTIVO | PASIVO | PATRIMONIO
//   cuenta   → nombre de la cuenta contable
//   categoria→ subcategoría del movimiento
//   mes      → 1‒12
//   trimestre→ T1 | T2 | T3 | T4
//   monto    → importe en la moneda base
//   pagado   → true si ya fue cobrado/pagado

import 'package:ffastdb/ffastdb.dart';
import 'package:ffastdb_analytics/ffastdb_analytics.dart';

Future<void> main() async {
  final db = await FfastDb.init(MemoryStorageStrategy());

  // ── Índices ────────────────────────────────────────────────────────────────
  db.addSortedIndex('tipo');
  db.addSortedIndex('mes');

  // ── Datos de ejemplo: 96 movimientos del ejercicio fiscal ──────────────────
  await _seedAsientos(db);

  // ══════════════════════════════════════════════════════════════════════════
  // 1. BALANCE POR TIPO DE CUENTA
  //    ¿Cuánto suman ingresos, gastos, activos, pasivos y patrimonio?
  // ══════════════════════════════════════════════════════════════════════════
  final balancePorTipo = await db.analytics.all.groupBy('tipo', {
    'total': aggSum('monto'),
    'movimientos': aggCount(),
    'promedio': aggAvg('monto'),
    'mayor': aggMax('monto'),
  });

  print('════ BALANCE POR TIPO DE CUENTA ════');
  for (final g in balancePorTipo) {
    final total = (g.aggregations['total'] as num).toStringAsFixed(2);
    final avg = (g.aggregations['promedio'] as num).toStringAsFixed(2);
    print('  ${g.key.toString().padRight(12)} '
        'total=\$$total  '
        'movimientos=${g.aggregations['movimientos']}  '
        'promedio=\$$avg');
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 2. ESTADO DE RESULTADOS — ingresos vs gastos por trimestre
  //    Filtramos sólo INGRESO y GASTO para calcular la utilidad operativa.
  // ══════════════════════════════════════════════════════════════════════════
  final ingresos = await db.analytics
      .where((q) => q.where('tipo').equals('INGRESO').findIds())
      .groupBy('trimestre', {'ingresos': aggSum('monto')});

  final gastos = await db.analytics
      .where((q) => q.where('tipo').equals('GASTO').findIds())
      .groupBy('trimestre', {'gastos': aggSum('monto')});

  final ingMap = {for (final g in ingresos) g.key as String: g.aggregations['ingresos'] as num};
  final gasMap = {for (final g in gastos) g.key as String: g.aggregations['gastos'] as num};

  print('\n════ ESTADO DE RESULTADOS (por trimestre) ════');
  print('  Trim.  Ingresos       Gastos         Utilidad');
  for (final t in ['T1', 'T2', 'T3', 'T4']) {
    final ing = ingMap[t] ?? 0;
    final gas = gasMap[t] ?? 0;
    final util = ing - gas;
    print('  $t     \$${ing.toStringAsFixed(2).padLeft(12)}  '
        '\$${gas.toStringAsFixed(2).padLeft(12)}  '
        '\$${util.toStringAsFixed(2).padLeft(12)}');
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 3. PIVOT — Gastos por categoría × trimestre
  //    Tabla cruzada para identificar dónde se concentran los costos.
  // ══════════════════════════════════════════════════════════════════════════
  final pivotGastos = await db.analytics
      .where((q) => q.where('tipo').equals('GASTO').findIds())
      .pivot(
        rowField: 'categoria',
        colField: 'trimestre',
        valueField: 'monto',
        aggregation: PivotAgg.sum,
      );

  print('\n════ GASTOS: categoría × trimestre (suma) ════');
  final cols = pivotGastos.columnKeys;
  print('  ${'Categoría'.padRight(20)} ${cols.map((c) => c.toString().padLeft(12)).join()}');
  for (final entry in pivotGastos.rows.entries) {
    final cells = cols
        .map((c) => '\$${((pivotGastos.rows[entry.key]?[c] as num?) ?? 0).toStringAsFixed(0).padLeft(11)}')
        .join();
    print('  ${entry.key.toString().padRight(20)}$cells');
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 4. CUENTAS POR COBRAR — cuentas no pagadas (activos pendientes)
  //    Top 5 movimientos con mayor monto pendiente de cobro.
  // ══════════════════════════════════════════════════════════════════════════
  final cxcTop5 = await db.analytics
      .where((q) => q.where('pagado').equals(false).findIds())
      .topN('monto', n: 5);

  print('\n════ TOP 5 CUENTAS POR COBRAR / PAGAR (pendientes) ════');
  for (final doc in cxcTop5) {
    print('  ${doc['cuenta'].toString().padRight(22)} '
        '\$${(doc['monto'] as num).toStringAsFixed(2).padLeft(10)}  '
        'tipo=${doc['tipo']}  mes=${doc['mes']}');
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 5. SUMA ACUMULADA DE INGRESOS — flujo de caja acumulado mes a mes
  //    Útil para ver si la empresa mantiene saldo positivo durante el año.
  // ══════════════════════════════════════════════════════════════════════════
  final ingresosMes = await db.analytics
      .where((q) => q.where('tipo').equals('INGRESO').findIds())
      .cumulativeSum('monto');

  print('\n════ FLUJO DE INGRESOS ACUMULADO (primeros 6 movimientos) ════');
  for (final p in ingresosMes.take(6)) {
    print('  movimiento ${(p.index + 1).toString().padLeft(3)}'
        '   monto=\$${p.value.toStringAsFixed(2).padLeft(10)}'
        '   acumulado=\$${p.cumSum.toStringAsFixed(2).padLeft(12)}');
  }
  print('  → Ingreso total acumulado: \$${ingresosMes.last.cumSum.toStringAsFixed(2)}');

  // ══════════════════════════════════════════════════════════════════════════
  // 6. MEDIA MÓVIL DE GASTOS (ventana 3 meses)
  //    Suaviza los picos para detectar tendencias en el gasto mensual.
  // ══════════════════════════════════════════════════════════════════════════
  final rollingGastos = await db.analytics
      .where((q) => q.where('tipo').equals('GASTO').findIds())
      .rollingAvg('monto', window: 3);

  print('\n════ MEDIA MÓVIL DE GASTOS (ventana=3) ════');
  for (final p in rollingGastos.take(8)) {
    print('  [${p.index}]  gasto=\$${p.value.toStringAsFixed(2).padLeft(10)}'
        '   media_móvil=\$${p.rollingValue.toStringAsFixed(2).padLeft(10)}');
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 7. DISTRIBUCIÓN DE MONTOS (histograma)
  //    ¿Los gastos están concentrados en importes pequeños o grandes?
  // ══════════════════════════════════════════════════════════════════════════
  final histGastos = await db.analytics
      .where((q) => q.where('tipo').equals('GASTO').findIds())
      .histogram('monto', bins: 4);

  print('\n════ HISTOGRAMA DE GASTOS (4 rangos) ════');
  for (final bin in histGastos) {
    final bar = '█' * bin.count;
    print('  \$${bin.low.toStringAsFixed(0).padLeft(8)} – '
        '\$${bin.high.toStringAsFixed(0).padRight(8)}  '
        '${bin.count.toString().padLeft(3)} mov.  $bar');
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 8. PERCENTIL 90 Y DESVIACIÓN ESTÁNDAR DE GASTOS
  //    Identifica montos atípicamente altos (posibles errores o fraudes).
  // ══════════════════════════════════════════════════════════════════════════
  final p90 = await db.analytics
      .where((q) => q.where('tipo').equals('GASTO').findIds())
      .percentile('monto', 0.90);

  final sd = await db.analytics
      .where((q) => q.where('tipo').equals('GASTO').findIds())
      .stddev('monto');

  print('\n════ ESTADÍSTICAS DE GASTOS ════');
  print('  Percentil 90      : \$${p90?.toStringAsFixed(2)}');
  print('  Desviación estándar: \$${sd?.toStringAsFixed(2)}');
  print('  Umbral de alerta   : \$${((p90 ?? 0) + (sd ?? 0)).toStringAsFixed(2)}'
      '  (p90 + 1σ)');

  // ══════════════════════════════════════════════════════════════════════════
  // 9. RANKING DE CUENTAS POR TOTAL GASTADO
  //    ¿Qué cuentas de gasto consumen más recursos?
  // ══════════════════════════════════════════════════════════════════════════
  final rankCuentas = await db.analytics
      .where((q) => q.where('tipo').equals('GASTO').findIds())
      .rank('monto');

  print('\n════ RANKING DE MOVIMIENTOS DE GASTO (mayor a menor) ════');
  for (final r in rankCuentas.take(5)) {
    print('  #${r.rank}  ${r.document['cuenta'].toString().padRight(22)}'
        '  \$${(r.value as num).toStringAsFixed(2).padLeft(10)}'
        '  mes=${r.document['mes']}');
  }

  await db.close();
}

// ─── Datos de ejemplo ─────────────────────────────────────────────────────────
//
// Simula los movimientos contables de "Empresa Demo S.A." durante un año fiscal.

Future<void> _seedAsientos(FastDB db) async {
  // Catálogo de cuentas por tipo
  const cuentas = {
    'INGRESO': [
      ('Ventas de productos', 'Ventas'),
      ('Servicios profesionales', 'Servicios'),
      ('Intereses bancarios', 'Financiero'),
    ],
    'GASTO': [
      ('Sueldos y salarios', 'Nómina'),
      ('Arriendo oficina', 'Infraestructura'),
      ('Publicidad y marketing', 'Marketing'),
      ('Servicios públicos', 'Infraestructura'),
      ('Mantenimiento equipos', 'Operacional'),
    ],
    'ACTIVO': [
      ('Caja y bancos', 'Liquidez'),
      ('Cuentas por cobrar', 'Liquidez'),
      ('Inventario', 'Operacional'),
    ],
    'PASIVO': [
      ('Cuentas por pagar', 'Corriente'),
      ('Préstamo bancario', 'Largo plazo'),
    ],
    'PATRIMONIO': [
      ('Capital social', 'Aportaciones'),
      ('Utilidades retenidas', 'Resultados'),
    ],
  };

  final trimestres = {1: 'T1', 2: 'T1', 3: 'T1', 4: 'T2', 5: 'T2', 6: 'T2', 7: 'T3', 8: 'T3', 9: 'T3', 10: 'T4', 11: 'T4', 12: 'T4'};

  int i = 0;
  for (final tipo in cuentas.keys) {
    for (final (cuenta, categoria) in cuentas[tipo]!) {
      for (int mes = 1; mes <= 12; mes++) {
        // Monto con variación realista según tipo y mes
        final base = switch (tipo) {
          'INGRESO' => 8000.0 + (mes * 200.0),
          'GASTO' => 1500.0 + (i % 5) * 400.0 + (mes * 50.0),
          'ACTIVO' => 5000.0 + (mes * 300.0),
          'PASIVO' => 3000.0 + (mes * 100.0),
          _ => 10000.0,
        };

        await db.insert({
          'tipo': tipo,
          'cuenta': cuenta,
          'categoria': categoria,
          'mes': mes,
          'trimestre': trimestres[mes],
          'monto': double.parse(base.toStringAsFixed(2)),
          'pagado': (i % 4) != 0, // 25 % pendientes de cobro/pago
        });
        i++;
      }
    }
  }
}

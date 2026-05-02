import 'package:ffastdb/ffastdb.dart';

/// Initialises the in-memory database and seeds it with accounting ledger data.
///
/// Schema per document:
///   tipo       → 'INGRESO' | 'GASTO' | 'ACTIVO' | 'PASIVO' | 'PATRIMONIO'
///   cuenta     → account name
///   categoria  → sub-category
///   mes        → 1‒12
///   trimestre  → 'T1' | 'T2' | 'T3' | 'T4'
///   monto      → amount (double)
///   pagado     → bool
class DbService {
  static Future<FastDB> init() async {
    // Usamos el singleton 'ffastdb' para una inicialización persistente 
    // multiplataforma (IndexedDB en Web, WAL en Nativo).
    final db = await ffastdb.init('ffastdb_analytics_demo');

    // Registramos los índices necesarios para la reactividad y ordenamiento.
    db.addSortedIndex('tipo');
    db.addSortedIndex('mes');
    db.addSortedIndex('trimestre');
    db.addSortedIndex('monto');
    db.addSortedIndex('categoria');

    // Forzamos el reindexado para asegurar que datos existentes sean procesados.
    await db.reindex();

    // await _seed(db); // Descomentar para sembrar datos iniciales si la DB está vacía
    return db;
  }

  static const _cuentas = {
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

  static const _trimestres = {
    1: 'T1', 2: 'T1', 3: 'T1',
    4: 'T2', 5: 'T2', 6: 'T2',
    7: 'T3', 8: 'T3', 9: 'T3',
    10: 'T4', 11: 'T4', 12: 'T4',
  };

  static Future<void> _seed(FastDB db) async {
    int i = 0;
    for (final tipo in _cuentas.keys) {
      for (final (cuenta, categoria) in _cuentas[tipo]!) {
        for (int mes = 1; mes <= 12; mes++) {
          final base = switch (tipo) {
            'INGRESO'    => 8000.0 + (mes * 200.0),
            'GASTO'      => 1500.0 + (i % 5) * 400.0 + (mes * 50.0),
            'ACTIVO'     => 5000.0 + (mes * 300.0),
            'PASIVO'     => 3000.0 + (mes * 100.0),
            _            => 10000.0,
          };
          await db.insert({
            'tipo':      tipo,
            'cuenta':    cuenta,
            'categoria': categoria,
            'mes':       mes,
            'trimestre': _trimestres[mes],
            'monto':     double.parse(base.toStringAsFixed(2)),
            'pagado':    (i % 4) != 0,
          });
          i++;
        }
      }
    }
  }
}

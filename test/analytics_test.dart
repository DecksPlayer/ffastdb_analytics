import 'package:ffastdb/ffastdb.dart';
import 'package:ffastdb_analytics/ffastdb_analytics.dart';
import 'package:test/test.dart';

// ─── Helpers ──────────────────────────────────────────────────────────────────

Future<FastDB> _freshDb(
  List<Map<String, dynamic>> docs, {
  List<String> sortedIndexes = const [],
}) async {
  final db = await FfastDb.init(MemoryStorageStrategy());
  for (final idx in sortedIndexes) {
    db.addSortedIndex(idx);
  }
  for (final d in docs) {
    await db.insert(d);
  }
  return db;
}

// ─── Fixtures ─────────────────────────────────────────────────────────────────

/// 6 sales records: 2 per category (A, B, C), values 10–60.
final _sales = [
  {'cat': 'A', 'region': 'N', 'amount': 10.0, 'active': true},
  {'cat': 'A', 'region': 'S', 'amount': 20.0, 'active': false},
  {'cat': 'B', 'region': 'N', 'amount': 30.0, 'active': true},
  {'cat': 'B', 'region': 'S', 'amount': 40.0, 'active': true},
  {'cat': 'C', 'region': 'N', 'amount': 50.0, 'active': false},
  {'cat': 'C', 'region': 'S', 'amount': 60.0, 'active': true},
];

void main() {
  // ── groupBy ─────────────────────────────────────────────────────────────────
  group('groupBy', () {
    late FastDB db;
    setUp(() async => db = await _freshDb(_sales));
    tearDown(() => db.close());

    test('sum per category', () async {
      final groups = await db.analytics.all.groupBy('cat', {
        'total': aggSum('amount'),
      });
      final byKey = {for (final g in groups) g.key as String: g};
      expect(byKey['A']!.aggregations['total'], equals(30.0));
      expect(byKey['B']!.aggregations['total'], equals(70.0));
      expect(byKey['C']!.aggregations['total'], equals(110.0));
    });

    test('count per category', () async {
      final groups = await db.analytics.all.groupBy('cat', {
        'n': aggCount(),
      });
      for (final g in groups) {
        expect(g.aggregations['n'], equals(2),
            reason: 'each category has 2 docs');
      }
    });

    test('avg per category', () async {
      final groups = await db.analytics.all.groupBy('cat', {
        'avg': aggAvg('amount'),
      });
      final byKey = {for (final g in groups) g.key as String: g};
      expect(byKey['A']!.aggregations['avg'], equals(15.0));
      expect(byKey['B']!.aggregations['avg'], equals(35.0));
      expect(byKey['C']!.aggregations['avg'], equals(55.0));
    });

    test('min and max per category', () async {
      final groups = await db.analytics.all.groupBy('cat', {
        'lo': aggMin('amount'),
        'hi': aggMax('amount'),
      });
      final byKey = {for (final g in groups) g.key as String: g};
      expect(byKey['A']!.aggregations['lo'], equals(10.0));
      expect(byKey['A']!.aggregations['hi'], equals(20.0));
    });

    test('GroupByResult.count reflects document count', () async {
      final groups = await db.analytics.all.groupBy('cat', {});
      for (final g in groups) {
        expect(g.count, equals(2));
      }
    });

    test('multiple aggregations in one call', () async {
      final groups = await db.analytics.all.groupBy('cat', {
        'total': aggSum('amount'),
        'n': aggCount(),
        'avg': aggAvg('amount'),
        'lo': aggMin('amount'),
        'hi': aggMax('amount'),
      });
      expect(groups, hasLength(3));
      for (final g in groups) {
        expect(g.aggregations.keys,
            containsAll(['total', 'n', 'avg', 'lo', 'hi']));
      }
    });
  });

  // ── percentile ──────────────────────────────────────────────────────────────
  group('percentile', () {
    late FastDB db;
    setUp(() async => db = await _freshDb(_sales));
    tearDown(() => db.close());

    test('p0 returns minimum', () async {
      final p0 = await db.analytics.all.percentile('amount', 0.0);
      expect(p0, equals(10.0));
    });

    test('p1 returns maximum', () async {
      final p1 = await db.analytics.all.percentile('amount', 1.0);
      expect(p1, equals(60.0));
    });

    test('p0.5 returns median value', () async {
      // sorted: [10, 20, 30, 40, 50, 60]  → index = round(0.5 * 5) = 3 → 40
      final median = await db.analytics.all.percentile('amount', 0.5);
      expect(median, equals(40.0));
    });

    test('returns null for empty collection', () async {
      final emptyDb = await FfastDb.init(MemoryStorageStrategy());
      final result = await emptyDb.analytics.all.percentile('amount', 0.5);
      expect(result, isNull);
      await emptyDb.close();
    });

    test('asserts p out of range', () async {
      expect(
        () => db.analytics.all.percentile('amount', 1.1),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  // ── stddev ──────────────────────────────────────────────────────────────────
  group('stddev', () {
    late FastDB db;
    setUp(() async => db = await _freshDb(_sales));
    tearDown(() => db.close());

    test('population stddev of [10,20,30,40,50,60]', () async {
      // mean=35, variance=((25^2+15^2+5^2+5^2+15^2+25^2)/6)=875/3≈291.67, σ≈17.08
      final sd = await db.analytics.all.stddev('amount');
      expect(sd, closeTo(17.08, 0.01));
    });

    test('returns null for empty collection', () async {
      final emptyDb = await FfastDb.init(MemoryStorageStrategy());
      final result = await emptyDb.analytics.all.stddev('amount');
      expect(result, isNull);
      await emptyDb.close();
    });

    test('stddev of single value is 0', () async {
      final singleDb = await _freshDb([
        {'v': 42.0}
      ]);
      final sd = await singleDb.analytics.all.stddev('v');
      expect(sd, equals(0.0));
      await singleDb.close();
    });
  });

  // ── histogram ───────────────────────────────────────────────────────────────
  group('histogram', () {
    late FastDB db;
    setUp(() async => db = await _freshDb(_sales));
    tearDown(() => db.close());

    test('produces requested number of bins', () async {
      final hist = await db.analytics.all.histogram('amount', bins: 3);
      expect(hist, hasLength(3));
    });

    test('all counts sum to total documents', () async {
      final hist = await db.analytics.all.histogram('amount', bins: 5);
      final total = hist.fold(0, (s, b) => s + b.count);
      expect(total, equals(6));
    });

    test('bins are contiguous (high == next low)', () async {
      final hist = await db.analytics.all.histogram('amount', bins: 4);
      for (int i = 0; i < hist.length - 1; i++) {
        expect(hist[i].high, closeTo(hist[i + 1].low, 1e-9));
      }
    });

    test('single unique value returns one bin', () async {
      final sameDb = await _freshDb([
        {'v': 5.0},
        {'v': 5.0},
      ]);
      final hist = await sameDb.analytics.all.histogram('v', bins: 3);
      expect(hist, hasLength(1));
      expect(hist.first.count, equals(2));
      await sameDb.close();
    });

    test('asserts bins > 0', () {
      expect(
        () => db.analytics.all.histogram('amount', bins: 0),
        throwsA(isA<AssertionError>()),
      );
    });

    test('empty collection returns empty list', () async {
      final emptyDb = await FfastDb.init(MemoryStorageStrategy());
      final hist = await emptyDb.analytics.all.histogram('amount');
      expect(hist, isEmpty);
      await emptyDb.close();
    });
  });

  // ── topN ────────────────────────────────────────────────────────────────────
  group('topN', () {
    late FastDB db;
    setUp(() async => db = await _freshDb(_sales));
    tearDown(() => db.close());

    test('returns exactly n documents', () async {
      final top = await db.analytics.all.topN('amount', n: 3);
      expect(top, hasLength(3));
    });

    test('descending order by default', () async {
      final top = await db.analytics.all.topN('amount', n: 3);
      expect(top[0]['amount'], equals(60.0));
      expect(top[1]['amount'], equals(50.0));
      expect(top[2]['amount'], equals(40.0));
    });

    test('ascending order', () async {
      final bot = await db.analytics.all.topN('amount', n: 2, ascending: true);
      expect(bot[0]['amount'], equals(10.0));
      expect(bot[1]['amount'], equals(20.0));
    });

    test('n larger than collection returns all docs', () async {
      final all = await db.analytics.all.topN('amount', n: 100);
      expect(all, hasLength(6));
    });
  });

  // ── rank ────────────────────────────────────────────────────────────────────
  group('rank', () {
    late FastDB db;
    setUp(() async => db = await _freshDb(_sales));
    tearDown(() => db.close());

    test('some document has rank 1', () async {
      final ranked = await db.analytics.all.rank('amount');
      expect(ranked.any((r) => r.rank == 1), isTrue);
    });

    test('highest amount gets rank 1 in descending mode', () async {
      final ranked = await db.analytics.all.rank('amount');
      final r1 = ranked.firstWhere((r) => r.rank == 1);
      expect(r1.value, equals(60.0));
    });

    test('produces one RankPoint per document', () async {
      final ranked = await db.analytics.all.rank('amount');
      expect(ranked, hasLength(6));
    });

    test('ties share same rank', () async {
      final tieDb = await _freshDb([
        {'v': 10.0},
        {'v': 10.0},
        {'v': 5.0},
      ]);
      db.addSortedIndex('v');
      final ranked = await tieDb.analytics.all.rank('v');
      final ranks = ranked.map((r) => r.rank).toList()..sort();
      expect(ranks.where((r) => r == 1), hasLength(2),
          reason: 'both 10.0 docs should share rank 1');
      await tieDb.close();
    });
  });

  // ── rollingAvg ──────────────────────────────────────────────────────────────
  group('rollingAvg', () {
    late FastDB db;
    setUp(() async => db = await _freshDb(_sales));
    tearDown(() => db.close());

    test('produces one point per document', () async {
      final pts = await db.analytics.all.rollingAvg('amount', window: 3);
      expect(pts, hasLength(6));
    });

    test('first point rolling value equals its own value (window=3)', () async {
      final pts = await db.analytics.all.rollingAvg('amount', window: 3);
      expect(pts.first.rollingValue, equals(pts.first.value));
    });

    test('window=1 rolling value always equals raw value', () async {
      final pts = await db.analytics.all.rollingAvg('amount', window: 1);
      for (final p in pts) {
        expect(p.rollingValue, closeTo(p.value, 1e-9));
      }
    });

    test('asserts window > 0', () {
      expect(
        () => db.analytics.all.rollingAvg('amount', window: 0),
        throwsA(isA<AssertionError>()),
      );
    });

    test('indices are sequential starting at 0', () async {
      final pts = await db.analytics.all.rollingAvg('amount', window: 2);
      for (int i = 0; i < pts.length; i++) {
        expect(pts[i].index, equals(i));
      }
    });
  });

  // ── cumulativeSum ───────────────────────────────────────────────────────────
  group('cumulativeSum', () {
    late FastDB db;
    setUp(() async => db = await _freshDb(_sales));
    tearDown(() => db.close());

    test('last cumSum equals total sum', () async {
      final pts = await db.analytics.all.cumulativeSum('amount');
      expect(pts.last.cumSum, equals(10 + 20 + 30 + 40 + 50 + 60.0));
    });

    test('cumSum is non-decreasing for positive values', () async {
      final pts = await db.analytics.all.cumulativeSum('amount');
      for (int i = 1; i < pts.length; i++) {
        expect(pts[i].cumSum, greaterThanOrEqualTo(pts[i - 1].cumSum));
      }
    });

    test('each point value matches the original document value', () async {
      final pts = await db.analytics.all.cumulativeSum('amount');
      final vals = pts.map((p) => p.value).toList();
      // All original amounts must appear in the sequence
      expect(vals, containsAll([10.0, 20.0, 30.0, 40.0, 50.0, 60.0]));
    });

    test('produces one point per document', () async {
      final pts = await db.analytics.all.cumulativeSum('amount');
      expect(pts, hasLength(6));
    });

    test('indices are sequential starting at 0', () async {
      final pts = await db.analytics.all.cumulativeSum('amount');
      for (int i = 0; i < pts.length; i++) {
        expect(pts[i].index, equals(i));
      }
    });
  });

  // ── pivot ───────────────────────────────────────────────────────────────────
  group('pivot', () {
    // 4 docs: region × quarter grid
    final pivotData = [
      {'region': 'N', 'q': 'Q1', 'revenue': 100.0},
      {'region': 'N', 'q': 'Q2', 'revenue': 200.0},
      {'region': 'S', 'q': 'Q1', 'revenue': 300.0},
      {'region': 'S', 'q': 'Q2', 'revenue': 400.0},
    ];

    late FastDB db;
    setUp(() async => db = await _freshDb(pivotData));
    tearDown(() => db.close());

    test('sum aggregation', () async {
      final t = await db.analytics.all.pivot(
        rowField: 'region',
        colField: 'q',
        valueField: 'revenue',
        aggregation: PivotAgg.sum,
      );
      expect(t.rows['N']!['Q1'], equals(100.0));
      expect(t.rows['S']!['Q2'], equals(400.0));
    });

    test('avg aggregation', () async {
      // Two docs with same region/q → avg
      final multiDb = await _freshDb([
        {'region': 'N', 'q': 'Q1', 'revenue': 100.0},
        {'region': 'N', 'q': 'Q1', 'revenue': 200.0},
      ]);
      final t = await multiDb.analytics.all.pivot(
        rowField: 'region',
        colField: 'q',
        valueField: 'revenue',
        aggregation: PivotAgg.avg,
      );
      expect(t.rows['N']!['Q1'], equals(150.0));
      await multiDb.close();
    });

    test('count aggregation', () async {
      final multiDb = await _freshDb([
        {'region': 'N', 'q': 'Q1', 'revenue': 10.0},
        {'region': 'N', 'q': 'Q1', 'revenue': 20.0},
        {'region': 'N', 'q': 'Q1', 'revenue': 30.0},
      ]);
      final t = await multiDb.analytics.all.pivot(
        rowField: 'region',
        colField: 'q',
        valueField: 'revenue',
        aggregation: PivotAgg.count,
      );
      expect(t.rows['N']!['Q1'], equals(3));
      await multiDb.close();
    });

    test('min and max aggregation', () async {
      final multiDb = await _freshDb([
        {'region': 'N', 'q': 'Q1', 'revenue': 10.0},
        {'region': 'N', 'q': 'Q1', 'revenue': 50.0},
      ]);
      final tMin = await multiDb.analytics.all.pivot(
        rowField: 'region',
        colField: 'q',
        valueField: 'revenue',
        aggregation: PivotAgg.min,
      );
      final tMax = await multiDb.analytics.all.pivot(
        rowField: 'region',
        colField: 'q',
        valueField: 'revenue',
        aggregation: PivotAgg.max,
      );
      expect(tMin.rows['N']!['Q1'], equals(10.0));
      expect(tMax.rows['N']!['Q1'], equals(50.0));
      await multiDb.close();
    });

    test('columnKeys contains all unique column values', () async {
      final t = await db.analytics.all.pivot(
        rowField: 'region',
        colField: 'q',
        valueField: 'revenue',
      );
      expect(t.columnKeys, containsAll(['Q1', 'Q2']));
    });

    test('missing cell returns null', () async {
      final sparseDb = await _freshDb([
        {'region': 'N', 'q': 'Q1', 'revenue': 10.0},
        // no N/Q2 row
        {'region': 'S', 'q': 'Q2', 'revenue': 20.0},
      ]);
      final t = await sparseDb.analytics.all.pivot(
        rowField: 'region',
        colField: 'q',
        valueField: 'revenue',
        aggregation: PivotAgg.sum,
      );
      expect(t.rows['N']!['Q2'], isNull);
      await sparseDb.close();
    });
  });

  // ── where (scoped analytics) ─────────────────────────────────────────────────
  group('where (scoped)', () {
    late FastDB db;
    setUp(() async {
      db = await _freshDb(_sales, sortedIndexes: ['active']);
    });
    tearDown(() => db.close());

    test('filters before aggregation', () async {
      final groups = await db.analytics
          .where((q) => q.where('active').equals(true).findIds())
          .groupBy('cat', {'total': aggSum('amount')});

      // active docs: A/10, B/30, B/40, C/60
      final byKey = {for (final g in groups) g.key as String: g};
      expect(byKey['A']!.aggregations['total'], equals(10.0));
      expect(byKey['B']!.aggregations['total'], equals(70.0));
      expect(byKey['C']!.aggregations['total'], equals(60.0));
    });

    test('topN on filtered subset', () async {
      final top = await db.analytics
          .where((q) => q.where('active').equals(false).findIds())
          .topN('amount', n: 5);
      // inactive docs: A/20, C/50
      expect(top, hasLength(2));
      expect(top.first['amount'], equals(50.0));
    });

    test('cumulativeSum on filtered subset sums only matching docs', () async {
      final pts = await db.analytics
          .where((q) => q.where('active').equals(false).findIds())
          .cumulativeSum('amount');
      // inactive: 20 + 50 = 70
      expect(pts.last.cumSum, equals(70.0));
    });
  });
}

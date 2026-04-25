import 'dart:async';
import 'dart:math' show sqrt;

import 'package:ffastdb/ffastdb.dart';

import 'agg_expr.dart';
import 'models.dart';

/// Function signature for pre-filtering documents before analytics.
typedef AnalyticsFilter = FutureOr<List<int>> Function(QueryBuilder q);

/// Scoped analytics query over a [FastDB] collection.
///
/// Obtain an instance via [AnalyticsCollection.all] or
/// [AnalyticsCollection.where]. All methods load documents lazily on each call.
///
/// Example:
/// ```dart
/// final result = await db.analytics.all.groupBy('category', {
///   'revenue': aggSum('price'),
///   'orders':  aggCount(),
/// });
/// ```
class AnalyticsQuery {
  final FastDB _db;
  final AnalyticsFilter? _filter;

  AnalyticsQuery(this._db, [this._filter]);

  // ─── Internal helpers ─────────────────────────────────────────────────────

  Future<List<dynamic>> _loadDocs() {
    final f = _filter;
    if (f != null) return _db.find(f);
    return _db.getAll();
  }

  List<double> _numericValues(List<dynamic> docs, String field) => docs
      .whereType<Map<String, dynamic>>()
      .map((d) => d[field])
      .whereType<num>()
      .map((n) => n.toDouble())
      .toList();

  // ─── Group By ─────────────────────────────────────────────────────────────

  /// Groups documents by [groupField] and computes [aggregations] per group.
  ///
  /// ```dart
  /// final groups = await db.analytics.all.groupBy('status', {
  ///   'total':     aggSum('price'),
  ///   'orders':    aggCount(),
  ///   'avg_price': aggAvg('price'),
  /// });
  /// ```
  Future<List<GroupByResult>> groupBy(
    String groupField,
    Map<String, AggExpr> aggregations,
  ) async {
    final docs = await _loadDocs();
    final groups = <dynamic, List<Map<String, dynamic>>>{};
    for (final doc in docs) {
      if (doc is Map<String, dynamic>) {
        groups.putIfAbsent(doc[groupField], () => []).add(doc);
      }
    }
    return groups.entries.map((entry) {
      final aggs = {
        for (final e in aggregations.entries)
          e.key: _applyGroupAgg(e.value, entry.value),
      };
      return GroupByResult(
          key: entry.key, count: entry.value.length, aggregations: aggs);
    }).toList();
  }

  dynamic _applyGroupAgg(AggExpr expr, List<Map<String, dynamic>> docs) {
    switch (expr) {
      case CountAgg():
        return docs.length;
      case SumAgg(:final field):
        return docs.fold<num>(
            0, (s, d) => s + (d[field] is num ? d[field] as num : 0));
      case AvgAgg(:final field):
        final vals = docs.map((d) => d[field]).whereType<num>().toList();
        if (vals.isEmpty) return null;
        return vals.fold<num>(0, (s, v) => s + v) / vals.length;
      case MinAgg(:final field):
        final vals =
            docs.map((d) => d[field]).whereType<Comparable>().toList();
        if (vals.isEmpty) return null;
        return vals.reduce((a, b) => a.compareTo(b) < 0 ? a : b);
      case MaxAgg(:final field):
        final vals =
            docs.map((d) => d[field]).whereType<Comparable>().toList();
        if (vals.isEmpty) return null;
        return vals.reduce((a, b) => a.compareTo(b) > 0 ? a : b);
    }
  }

  // ─── Distributions ────────────────────────────────────────────────────────

  /// Returns the value at rank [p] (0.0–1.0) for [field].
  ///
  /// `percentile('latency', 0.95)` → 95th percentile.
  Future<double?> percentile(String field, double p) async {
    assert(p >= 0.0 && p <= 1.0, 'p must be between 0.0 and 1.0');
    final values = _numericValues(await _loadDocs(), field)..sort();
    if (values.isEmpty) return null;
    return values[((p * (values.length - 1)).round())];
  }

  /// Population standard deviation of the numeric values of [field].
  Future<double?> stddev(String field) async {
    final values = _numericValues(await _loadDocs(), field);
    if (values.isEmpty) return null;
    final mean = values.fold(0.0, (s, v) => s + v) / values.length;
    final variance =
        values.fold(0.0, (s, v) => s + (v - mean) * (v - mean)) /
            values.length;
    return sqrt(variance);
  }

  /// Frequency distribution of [field] divided into [bins] equal-width bins.
  Future<List<HistogramBin>> histogram(String field, {int bins = 10}) async {
    assert(bins > 0, 'bins must be > 0');
    final values = _numericValues(await _loadDocs(), field);
    if (values.isEmpty) return [];

    final minVal = values.fold(values.first, (a, b) => a < b ? a : b);
    final maxVal = values.fold(values.first, (a, b) => a > b ? a : b);

    if (minVal == maxVal) {
      return [HistogramBin(low: minVal, high: maxVal, count: values.length)];
    }

    final binWidth = (maxVal - minVal) / bins;
    final counts = List<int>.filled(bins, 0);
    for (final v in values) {
      counts[((v - minVal) / binWidth).floor().clamp(0, bins - 1)]++;
    }
    return List.generate(
      bins,
      (i) => HistogramBin(
        low: minVal + i * binWidth,
        high: minVal + (i + 1) * binWidth,
        count: counts[i],
      ),
    );
  }

  // ─── Rankings ─────────────────────────────────────────────────────────────

  /// Returns the top [n] documents sorted by [field] (descending by default).
  Future<List<Map<String, dynamic>>> topN(
    String field, {
    int n = 10,
    bool ascending = false,
  }) async {
    final docs = (await _loadDocs())
        .whereType<Map<String, dynamic>>()
        .where((d) => d[field] is Comparable)
        .toList()
      ..sort((a, b) {
        final av = a[field] as Comparable;
        final bv = b[field] as Comparable;
        return ascending ? av.compareTo(bv) : bv.compareTo(av);
      });
    return docs.take(n).toList();
  }

  /// Assigns a rank to every document sorted by [field].
  ///
  /// Ties receive the same rank (standard competition ranking: 1, 1, 3…).
  Future<List<RankPoint>> rank(String field, {bool ascending = false}) async {
    final docs = (await _loadDocs())
        .whereType<Map<String, dynamic>>()
        .where((d) => d[field] is Comparable)
        .toList();

    final indexed = docs.asMap().entries.toList()
      ..sort((a, b) {
        final av = a.value[field] as Comparable;
        final bv = b.value[field] as Comparable;
        return ascending ? av.compareTo(bv) : bv.compareTo(av);
      });

    final ranks = List<int>.filled(docs.length, 0);
    int currentRank = 1;
    for (int i = 0; i < indexed.length; i++) {
      if (i > 0) {
        final prev = indexed[i - 1].value[field] as Comparable;
        if (prev.compareTo(indexed[i].value[field]) != 0) currentRank = i + 1;
      }
      ranks[indexed[i].key] = currentRank;
    }

    return docs
        .asMap()
        .entries
        .map((e) => RankPoint(
              document: e.value,
              rank: ranks[e.key],
              value: e.value[field],
            ))
        .toList();
  }

  // ─── Window Functions ─────────────────────────────────────────────────────

  /// Rolling average of [valueField] over a sliding [window].
  ///
  /// Optionally order by [orderBy] before computing.
  Future<List<RollingPoint>> rollingAvg(
    String valueField, {
    required int window,
    String? orderBy,
  }) async {
    assert(window > 0, 'window must be > 0');
    final docs = (await _loadDocs())
        .whereType<Map<String, dynamic>>()
        .where((d) => d[valueField] is num)
        .toList();

    if (orderBy != null) {
      docs.sort((a, b) {
        final av = a[orderBy];
        final bv = b[orderBy];
        return (av is Comparable && bv is Comparable) ? av.compareTo(bv) : 0;
      });
    }

    return List.generate(docs.length, (i) {
      final start = (i - window + 1).clamp(0, i);
      final slice = docs.sublist(start, i + 1);
      final avg =
          slice.fold(0.0, (s, d) => s + (d[valueField] as num).toDouble()) /
              slice.length;
      return RollingPoint(
        index: i,
        value: (docs[i][valueField] as num).toDouble(),
        rollingValue: avg,
      );
    });
  }

  /// Running (cumulative) sum of [valueField].
  ///
  /// Optionally order by [orderBy] before computing.
  Future<List<CumSumPoint>> cumulativeSum(
    String valueField, {
    String? orderBy,
  }) async {
    final docs = (await _loadDocs())
        .whereType<Map<String, dynamic>>()
        .where((d) => d[valueField] is num)
        .toList();

    if (orderBy != null) {
      docs.sort((a, b) {
        final av = a[orderBy];
        final bv = b[orderBy];
        return (av is Comparable && bv is Comparable) ? av.compareTo(bv) : 0;
      });
    }

    double cumSum = 0;
    return List.generate(docs.length, (i) {
      final val = (docs[i][valueField] as num).toDouble();
      cumSum += val;
      return CumSumPoint(index: i, value: val, cumSum: cumSum);
    });
  }

  // ─── Pivot ────────────────────────────────────────────────────────────────

  /// Cross-tabulation of [rowField] × [colField] aggregating [valueField].
  ///
  /// ```dart
  /// final table = await db.analytics.all.pivot(
  ///   rowField:    'region',
  ///   colField:    'quarter',
  ///   valueField:  'revenue',
  ///   aggregation: PivotAgg.sum,
  /// );
  /// print(table.rows['EMEA']['Q1']); // e.g. 120000
  /// ```
  Future<PivotTable> pivot({
    required String rowField,
    required String colField,
    required String valueField,
    PivotAgg aggregation = PivotAgg.sum,
  }) async {
    final docs = await _loadDocs();
    final rowKeys = <dynamic>{};
    final colKeys = <dynamic>{};
    final buckets = <dynamic, Map<dynamic, List<num>>>{};

    for (final doc in docs) {
      if (doc is! Map<String, dynamic>) continue;
      final rowVal = doc[rowField];
      final colVal = doc[colField];
      final numVal = doc[valueField];
      if (rowVal == null || colVal == null) continue;
      rowKeys.add(rowVal);
      colKeys.add(colVal);
      if (numVal is num) {
        ((buckets[rowVal] ??= {})[colVal] ??= []).add(numVal);
      }
    }

    final rows = <dynamic, Map<dynamic, dynamic>>{
      for (final rowKey in rowKeys)
        rowKey: {
          for (final colKey in colKeys)
            colKey: _applyPivotAgg(aggregation, buckets[rowKey]?[colKey] ?? []),
        },
    };

    return PivotTable(
      rowField: rowField,
      colField: colField,
      valueField: valueField,
      rows: rows,
      columnKeys: colKeys.toList(),
    );
  }

  dynamic _applyPivotAgg(PivotAgg agg, List<num> values) {
    if (values.isEmpty) return null;
    return switch (agg) {
      PivotAgg.sum => values.fold<num>(0, (s, v) => s + v),
      PivotAgg.avg => values.fold<num>(0, (s, v) => s + v) / values.length,
      PivotAgg.count => values.length,
      PivotAgg.min => values.reduce((a, b) => a < b ? a : b),
      PivotAgg.max => values.reduce((a, b) => a > b ? a : b),
    };
  }
}

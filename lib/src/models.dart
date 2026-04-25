/// Result of a single group from [AnalyticsQuery.groupBy].
class GroupByResult {
  /// The value of the group-by field for this group.
  final dynamic key;

  /// Number of documents in this group.
  final int count;

  /// Computed aggregation values, keyed by the name you provided.
  final Map<String, dynamic> aggregations;

  const GroupByResult({
    required this.key,
    required this.count,
    required this.aggregations,
  });

  @override
  String toString() =>
      'GroupByResult(key: $key, count: $count, aggregations: $aggregations)';
}

/// A single bin in a [AnalyticsQuery.histogram] result.
///
/// Represents the half-open interval `[low, high)` with [count] values.
class HistogramBin {
  final double low;
  final double high;
  final int count;

  const HistogramBin({
    required this.low,
    required this.high,
    required this.count,
  });

  @override
  String toString() => 'HistogramBin([${low.toStringAsFixed(2)}, '
      '${high.toStringAsFixed(2)}): $count)';
}

/// A data point in a [AnalyticsQuery.rollingAvg] result.
class RollingPoint {
  /// Zero-based position in the ordered sequence.
  final int index;

  /// Original value at this position.
  final double value;

  /// Rolling average value at this position (over the configured window).
  final double rollingValue;

  const RollingPoint({
    required this.index,
    required this.value,
    required this.rollingValue,
  });
}

/// A data point in a [AnalyticsQuery.cumulativeSum] result.
class CumSumPoint {
  /// Zero-based position in the ordered sequence.
  final int index;

  /// Original value at this position.
  final double value;

  /// Running total up to and including this position.
  final double cumSum;

  const CumSumPoint({
    required this.index,
    required this.value,
    required this.cumSum,
  });
}

/// A document with its computed rank from [AnalyticsQuery.rank].
class RankPoint {
  final Map<String, dynamic> document;

  /// 1-based rank. Ties share the same rank (standard competition ranking).
  final int rank;

  /// The value of the ranked field.
  final dynamic value;

  const RankPoint({
    required this.document,
    required this.rank,
    required this.value,
  });
}

/// Result of a [AnalyticsQuery.pivot] operation.
///
/// Access cell values via `rows[rowValue][colValue]`.
class PivotTable {
  final String rowField;
  final String colField;
  final String valueField;

  /// `rows[rowValue][colValue]` = aggregated cell value (or `null` if no data).
  final Map<dynamic, Map<dynamic, dynamic>> rows;

  /// Ordered list of unique column values (the pivot column headers).
  final List<dynamic> columnKeys;

  const PivotTable({
    required this.rowField,
    required this.colField,
    required this.valueField,
    required this.rows,
    required this.columnKeys,
  });
}

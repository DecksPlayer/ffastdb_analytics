/// Aggregation expressions for [AnalyticsQuery.groupBy].
///
/// Use the convenience constructors at the bottom of this file:
/// [aggSum], [aggAvg], [aggCount], [aggMin], [aggMax].
sealed class AggExpr {
  const AggExpr();
}

/// Sum the numeric values of [field] within the group.
final class SumAgg extends AggExpr {
  final String field;
  const SumAgg(this.field);
}

/// Average of the numeric values of [field] within the group.
final class AvgAgg extends AggExpr {
  final String field;
  const AvgAgg(this.field);
}

/// Count of documents in the group (no field needed).
final class CountAgg extends AggExpr {
  const CountAgg();
}

/// Minimum value of [field] within the group.
final class MinAgg extends AggExpr {
  final String field;
  const MinAgg(this.field);
}

/// Maximum value of [field] within the group.
final class MaxAgg extends AggExpr {
  final String field;
  const MaxAgg(this.field);
}

// ─── Convenience constructors ─────────────────────────────────────────────

SumAgg aggSum(String field) => SumAgg(field);
AvgAgg aggAvg(String field) => AvgAgg(field);
CountAgg aggCount() => const CountAgg();
MinAgg aggMin(String field) => MinAgg(field);
MaxAgg aggMax(String field) => MaxAgg(field);

/// Aggregation mode used by [AnalyticsQuery.pivot].
enum PivotAgg { sum, avg, count, min, max }

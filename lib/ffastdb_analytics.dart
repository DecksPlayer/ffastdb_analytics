/// # ffastdb_analytics
///
/// A high-performance analytical query engine built on top of
/// [ffastdb](https://pub.dev/packages/ffastdb). Brings **OLAP-class**
/// capabilities — aggregations, window functions, distributions, ranking,
/// pivoting and time-series analysis — directly into your Dart/Flutter app,
/// with zero external services and full offline support.
///
/// ---
///
/// ## Quick start
///
/// ```dart
/// import 'package:ffastdb/ffastdb.dart';
/// import 'package:ffastdb_analytics/ffastdb_analytics.dart';
///
/// final db = await FfastDb.init(MemoryStorageStrategy());
/// // ... insert documents ...
///
/// // Full-collection analytics
/// final summary = await db.analytics.all.groupBy('category', {
///   'revenue':  aggSum('amount'),
///   'orders':   aggCount(),
///   'avg_ticket': aggAvg('amount'),
/// });
///
/// // Scoped analytics — filter first, then aggregate
/// final activeRevenue = await db.analytics
///     .where((q) => q.where('status').equals('active').findIds())
///     .groupBy('region', {'total': aggSum('amount')});
/// ```
///
/// ---
///
/// ## Feature matrix
///
/// | Category | Operation | API |
/// |---|---|---|
/// | **Aggregation** | Sum, Avg, Count, Min, Max per group | [AnalyticsQuery.groupBy] |
/// | **Distribution** | Percentile (any rank 0–1) | [AnalyticsQuery.percentile] |
/// | **Distribution** | Population standard deviation | [AnalyticsQuery.stddev] |
/// | **Distribution** | Equal-width histogram | [AnalyticsQuery.histogram] |
/// | **Ranking** | Top-N documents by field | [AnalyticsQuery.topN] |
/// | **Ranking** | Dense rank with tie handling | [AnalyticsQuery.rank] |
/// | **Window** | Rolling / moving average | [AnalyticsQuery.rollingAvg] |
/// | **Window** | Cumulative sum (running total) | [AnalyticsQuery.cumulativeSum] |
/// | **Pivot** | Cross-tabulation (row × col → value) | [AnalyticsQuery.pivot] |
/// | **Scoping** | Pre-filter via any ffastdb query | [AnalyticsCollection.where] |
///
/// ---
///
/// ## Aggregation functions
///
/// All aggregation expressions are composable and passed as a `Map` to
/// [AnalyticsQuery.groupBy]:
///
/// | Function | Description | Constructor |
/// |---|---|---|
/// | `SumAgg` | Sum of a numeric field | `aggSum('field')` |
/// | `AvgAgg` | Arithmetic mean | `aggAvg('field')` |
/// | `CountAgg` | Document count (no field required) | `aggCount()` |
/// | `MinAgg` | Minimum comparable value | `aggMin('field')` |
/// | `MaxAgg` | Maximum comparable value | `aggMax('field')` |
///
/// ---
///
/// ## Window functions
///
/// Window functions operate on an ordered sequence of documents and produce
/// one output row per input row, similar to SQL `OVER (...)` clauses.
///
/// ### Rolling average
/// ```dart
/// // 7-period moving average of daily sales, ordered by date
/// final rolling = await db.analytics.all
///     .rollingAvg('amount', window: 7, orderBy: 'date');
/// ```
///
/// ### Cumulative sum
/// ```dart
/// // Running total of cash inflows
/// final cs = await db.analytics
///     .where((q) => q.where('type').equals('INCOME').findIds())
///     .cumulativeSum('amount');
/// print('Year-to-date: \$${cs.last.cumSum}');
/// ```
///
/// ---
///
/// ## Pivot tables
///
/// Produce a cross-tabulation matrix in a single call:
///
/// ```dart
/// final table = await db.analytics.all.pivot(
///   rowField:    'department',
///   colField:    'quarter',
///   valueField:  'budget',
///   aggregation: PivotAgg.sum,   // sum | avg | count | min | max
/// );
///
/// // Access cell values
/// final q1Engineering = table.rows['Engineering']?['Q1']; // num?
/// ```
///
/// ---
///
/// ## Statistical analysis
///
/// ```dart
/// // 95th-percentile response time
/// final p95 = await db.analytics.all.percentile('latency_ms', 0.95);
///
/// // Population std-dev — detect outliers
/// final sigma = await db.analytics.all.stddev('amount');
///
/// // Equal-width histogram — understand value distribution
/// final hist = await db.analytics.all.histogram('price', bins: 10);
/// for (final bin in hist) {
///   print('[${bin.low.toStringAsFixed(2)}, ${bin.high.toStringAsFixed(2)}): '
///         '${bin.count} docs');
/// }
/// ```
///
/// ---
///
/// ## Scoped (filtered) analytics
///
/// Every analytical method can be scoped to a subset of documents using the
/// full expressiveness of the ffastdb query builder. Filtering happens before
/// any aggregation, so only relevant documents are processed:
///
/// ```dart
/// // P90 latency only for requests that returned HTTP 500
/// final p90 = await db.analytics
///     .where((q) => q.where('status').equals(500).findIds())
///     .percentile('latency_ms', 0.90);
///
/// // Revenue breakdown for a specific country
/// final breakdown = await db.analytics
///     .where((q) => q.where('country').equals('MX').findIds())
///     .groupBy('product', {'revenue': aggSum('amount')});
/// ```
///
/// ---
///
/// ## Design goals
///
/// * **Embedded-first** — runs fully in-process; no server, no HTTP, no SQL
///   dialect to learn.
/// * **Offline-capable** — works in Flutter apps with no network dependency.
/// * **Composable** — filter with [AnalyticsCollection.where], then chain any
///   analytical method.
/// * **Type-safe** — sealed [AggExpr] hierarchy exhaustively handled at
///   compile time; no stringly-typed aggregation names.
/// * **Lazy loading** — documents are fetched from storage on each call,
///   keeping memory pressure low.
library;
export 'src/agg_expr.dart';
export 'src/models.dart';
export 'src/analytics_query.dart';
export 'src/analytics_collection.dart';

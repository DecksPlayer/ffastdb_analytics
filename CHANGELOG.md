# Changelog

All notable changes to this project will be documented in this file.

## 0.1.0 — 2026-04-25

Initial release.

### Added

**Aggregation**
- `groupBy(field, aggregations)` — groups documents by a field and computes aggregations per group.
- Aggregation expressions: `aggSum`, `aggAvg`, `aggCount`, `aggMin`, `aggMax`.

**Distribution**
- `percentile(field, p)` — value at rank `p` (0.0–1.0) for any numeric field.
- `stddev(field)` — population standard deviation.
- `histogram(field, {bins})` — equal-width frequency distribution.

**Ranking**
- `topN(field, {n, ascending})` — top-N documents sorted by a field.
- `rank(field, {ascending})` — dense rank with standard competition tie handling (1, 1, 3…).

**Window functions**
- `rollingAvg(valueField, {window, orderBy})` — sliding window moving average.
- `cumulativeSum(valueField, {orderBy})` — running cumulative sum.

**Pivot**
- `pivot(rowField, colField, valueField, {agg})` — cross-tabulation (row × col → value) with `sum`, `avg`, `count`, `min`, or `max`.

**Scoping**
- `AnalyticsCollection.all` — runs analytics over the entire collection.
- `AnalyticsCollection.where(filter)` — pre-filters documents using any `ffastdb` query before analytics.

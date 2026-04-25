# ffastdb_analytics

[![pub.dev](https://img.shields.io/pub/v/ffastdb_analytics)](https://pub.dev/packages/ffastdb_analytics)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Powerful analytics for your [ffastdb](https://pub.dev/packages/ffastdb) database — group, rank, pivot, and compute statistics directly inside your Dart or Flutter app, with no server, no network, and no SQL required.

---

## What can I do with it?

| I want to… | Use |
|---|---|
| Sum / average / count records by category | `groupBy` |
| Find the top-N items by a value | `topN` |
| Rank items with tie support | `rank` |
| Compute a moving average over time | `rollingAvg` |
| Build a running total | `cumulativeSum` |
| Generate a spreadsheet-style pivot table | `pivot` |
| Calculate a percentile (e.g. p95 latency) | `percentile` |
| Measure spread with standard deviation | `stddev` |
| See how values are distributed | `histogram` |
| Narrow down results before analysing | `where` |

---

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  ffastdb_analytics: ^0.1.0
```

Then run:

```sh
dart pub get
```

---

## Quick start

```dart
import 'package:ffastdb/ffastdb.dart';
import 'package:ffastdb_analytics/ffastdb_analytics.dart';

final db = await FfastDb.init(MemoryStorageStrategy());

// Insert some documents
await db.insertMany([
  {'category': 'Food',  'amount': 120.0, 'status': 'active'},
  {'category': 'Food',  'amount':  80.0, 'status': 'active'},
  {'category': 'Tech',  'amount': 500.0, 'status': 'inactive'},
]);

// Analyse the whole collection
final summary = await db.analytics.all.groupBy('category', {
  'revenue':    aggSum('amount'),
  'orders':     aggCount(),
  'avg_ticket': aggAvg('amount'),
});
// → [{key: Food, revenue: 200.0, orders: 2, avg_ticket: 100.0}, ...]

// Or filter first, then analyse
final activeOnly = await db.analytics
    .where((q) => q.where('status').equals('active').findIds())
    .groupBy('category', {'total': aggSum('amount')});
```

> **Tip:** Every analytical method works the same way whether you use `.all` or `.where(...)` — just pick the scope you need.

---

## Aggregations

Use `groupBy` to split documents into groups and compute values for each group. Pass any combination of aggregation expressions:

| Expression | Description |
|---|---|
| `aggSum('field')` | Total of a numeric field |
| `aggAvg('field')` | Average of a numeric field |
| `aggCount()` | Number of documents in the group |
| `aggMin('field')` | Smallest value |
| `aggMax('field')` | Largest value |

```dart
final result = await db.analytics.all.groupBy('department', {
  'headcount': aggCount(),
  'total_salary': aggSum('salary'),
  'avg_salary': aggAvg('salary'),
  'min_salary': aggMin('salary'),
  'max_salary': aggMax('salary'),
});
```

---

## Ranking

### Top-N

Get the highest (or lowest) N documents by any field:

```dart
// Top 5 products by revenue
final top5 = await db.analytics.all.topN('revenue', n: 5);

// Bottom 3 (ascending)
final bottom3 = await db.analytics.all.topN('revenue', n: 3, ascending: true);
```

### Dense rank

Assign a rank to every document. Ties share the same rank:

```dart
final ranked = await db.analytics.all.rank('score');
// scores [100, 100, 80] → ranks [1, 1, 3]

for (final r in ranked) {
  print('#${r.rank}  ${r.document['name']}  score=${r.value}');
}
```

---

## Window functions

Window functions compute a value for each document based on a sliding window over an ordered sequence — like Excel's moving-average formula or SQL's `OVER (...)`.

### Rolling average

```dart
// 7-day moving average of daily revenue
final rolling = await db.analytics.all
    .rollingAvg('amount', window: 7, orderBy: 'date');

for (final p in rolling) {
  print('day ${p.index}: value=${p.value}  7-day avg=${p.rollingValue}');
}
```

### Cumulative sum

```dart
// Year-to-date running total for income entries
final ytd = await db.analytics
    .where((q) => q.where('type').equals('INCOME').findIds())
    .cumulativeSum('amount', orderBy: 'date');

print('YTD total: \$${ytd.last.cumSum}');
```

---

## Pivot tables

Turn rows into a spreadsheet-style grid — perfect for comparing values across two dimensions:

```dart
final table = await db.analytics.all.pivot(
  rowField:    'department',
  colField:    'quarter',
  valueField:  'budget',
  aggregation: PivotAgg.sum,   // sum | avg | count | min | max
);

// Read a single cell
final q1Eng = table.rows['Engineering']?['Q1']; // num?

// Print the whole grid
print(['', ...table.columnKeys].join('\t'));
for (final entry in table.rows.entries) {
  final cells = table.columnKeys
      .map((c) => table.rows[entry.key]?[c]?.toString() ?? '-')
      .join('\t');
  print('${entry.key}\t$cells');
}
```

---

## Statistics

### Percentile

Find the value below which a given percentage of data falls — great for SLA thresholds:

```dart
final p95latency = await db.analytics.all.percentile('latency_ms', 0.95);
print('95th percentile latency: ${p95latency}ms');
```

### Standard deviation

Measure how spread out values are — useful for detecting outliers:

```dart
final sigma = await db.analytics.all.stddev('amount');
```

### Histogram

Understand the shape of your data by splitting it into equal-width buckets:

```dart
final hist = await db.analytics.all.histogram('price', bins: 10);
for (final bin in hist) {
  print('[${bin.low.toStringAsFixed(2)} – ${bin.high.toStringAsFixed(2)}): '
        '${bin.count} items');
}
```

---

## Full example — Accounting ledger

```dart
// 1. Balance grouped by account type
final balance = await db.analytics.all.groupBy('type', {
  'total':      aggSum('amount'),
  'entries':    aggCount(),
  'avg_amount': aggAvg('amount'),
});

// 2. Revenue vs expenses per quarter
final revenue = await db.analytics
    .where((q) => q.where('type').equals('INCOME').findIds())
    .groupBy('quarter', {'total': aggSum('amount')});

final expenses = await db.analytics
    .where((q) => q.where('type').equals('EXPENSE').findIds())
    .groupBy('quarter', {'total': aggSum('amount')});

// 3. Expense breakdown as a pivot (category × quarter)
final breakdown = await db.analytics
    .where((q) => q.where('type').equals('EXPENSE').findIds())
    .pivot(
      rowField:    'category',
      colField:    'quarter',
      valueField:  'amount',
      aggregation: PivotAgg.sum,
    );

// 4. Flag unusually large transactions (above p90 + 1σ)
final p90       = await db.analytics.all.percentile('amount', 0.90);
final sigma     = await db.analytics.all.stddev('amount');
final threshold = (p90 ?? 0) + (sigma ?? 0);
```

---

## How it works

Every analytics operation follows the same two-step pattern:

1. **Scope** — decide which documents to include using `.all` or `.where(filter)`.
2. **Analyse** — call any analytical method on that scope.

```
db.analytics
  .where(...)     ← optional filter (any ffastdb query)
  .groupBy(...)   ← or any other analytical method
```

Documents are loaded lazily from storage on each call, so memory usage stays low even for large collections.

---

## License

[MIT](LICENSE)

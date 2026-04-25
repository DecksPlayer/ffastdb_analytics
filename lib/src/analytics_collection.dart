import 'package:ffastdb/ffastdb.dart';

import 'analytics_query.dart';

/// Entry point for analytics operations on a [FastDB] instance.
///
/// Access via the [FastDBAnalyticsExtension.analytics] getter:
/// ```dart
/// final db = await FfastDb.init(MemoryStorageStrategy());
///
/// // All documents
/// final groups = await db.analytics.all.groupBy('category', {
///   'revenue': aggSum('price'),
///   'orders':  aggCount(),
/// });
///
/// // Filtered documents
/// final p95 = await db.analytics
///   .where((q) => q.where('status').equals('active'))
///   .percentile('latency', 0.95);
/// ```
class AnalyticsCollection {
  final FastDB _db;

  AnalyticsCollection(this._db);

  /// Run analytics over ALL documents in the collection.
  AnalyticsQuery get all => AnalyticsQuery(_db);

  /// Scope analytics to documents matching [filter].
  ///
  /// The [filter] receives a [QueryBuilder] and must return the matching
  /// document IDs — the same signature as [FastDB.find].
  AnalyticsQuery where(AnalyticsFilter filter) =>
      AnalyticsQuery(_db, filter);
}

/// Adds the [analytics] getter to every [FastDB] instance.
extension FastDBAnalyticsExtension on FastDB {
  AnalyticsCollection get analytics => AnalyticsCollection(this);
}

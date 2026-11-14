/// The request a grid makes of its data source.
library;

import 'aggregate.dart';
import 'decoration.dart';
import 'fetch.dart';
import 'filter.dart';
import 'group.dart';
import 'sort.dart';

/// A complete description of what the grid wants to show.
///
/// Everything the view state implies - ordering, filtering, grouping, the
/// search box, the current page - is collected here and handed to a
/// [LatticeDataSource]. An in-memory source executes it locally; a remote
/// source translates it into SQL or query parameters. The grid itself never
/// assumes which.
class GridQuery {
  const GridQuery({
    this.sorts = const [],
    this.filter,
    this.search = '',
    this.searchFields = const [],
    this.groups = const [],
    this.aggregations = const [],
    this.offset = 0,
    this.limit,
    this.signal,
  });

  final List<SortSpec> sorts;

  /// Structured filter tree from the filter row or filter builder.
  final Filter? filter;

  /// Free-text search applied across [searchFields], or across every visible
  /// column when that is empty.
  final String search;
  final List<String> searchFields;

  final List<GroupSpec> groups;

  /// Aggregates to compute for group rows and the footer.
  final List<Aggregation> aggregations;

  /// First row to return.
  final int offset;

  /// Maximum number of rows to return; `null` means all of them.
  final int? limit;

  /// Tells the source the grid has given up on this fetch, so a remote
  /// request can be aborted rather than merely ignored when it lands.
  ///
  /// Null when the query was built by hand. Not part of [toJson]: it
  /// describes one attempt, not what the grid wants to show.
  final FetchSignal? signal;

  bool get hasSearch => search.trim().isNotEmpty;
  bool get isGrouped => groups.isNotEmpty;
  bool get isPaged => limit != null;

  GridQuery copyWith({
    List<SortSpec>? sorts,
    Filter? filter,
    bool clearFilter = false,
    String? search,
    List<String>? searchFields,
    List<GroupSpec>? groups,
    List<Aggregation>? aggregations,
    int? offset,
    int? limit,
    bool clearLimit = false,
    FetchSignal? signal,
  }) {
    return GridQuery(
      sorts: sorts ?? this.sorts,
      filter: clearFilter ? null : (filter ?? this.filter),
      search: search ?? this.search,
      searchFields: searchFields ?? this.searchFields,
      groups: groups ?? this.groups,
      aggregations: aggregations ?? this.aggregations,
      offset: offset ?? this.offset,
      limit: clearLimit ? null : (limit ?? this.limit),
      signal: signal ?? this.signal,
    );
  }

  Map<String, Object?> toJson() => {
        if (sorts.isNotEmpty) 'sorts': [for (final s in sorts) s.toJson()],
        if (filter != null) 'filter': filter!.toJson(),
        if (hasSearch) 'search': search,
        if (searchFields.isNotEmpty) 'searchFields': searchFields,
        if (groups.isNotEmpty) 'groups': [for (final g in groups) g.toJson()],
        if (offset != 0) 'offset': offset,
        if (limit != null) 'limit': limit,
      };

  /// Rebuilds a query produced by [toJson].
  ///
  /// [aggregations] cannot be serialised - an [Aggregation] may carry a
  /// reducer function - so they are passed back in. Neither is the
  /// cancellation [signal], which belongs to one attempt rather than to the
  /// query, nor a [GroupSpec]'s bucketing functions; see [GroupSpec.restore].
  static GridQuery fromJson(
    Map<String, Object?> json, {
    List<Aggregation> aggregations = const [],
  }) {
    return GridQuery(
      sorts: [
        for (final s in (json['sorts'] as List? ?? const []))
          SortSpec.fromJson((s as Map).cast<String, Object?>()),
      ],
      filter: json['filter'] == null
          ? null
          : Filter.fromJson((json['filter']! as Map).cast<String, Object?>()),
      search: json['search'] as String? ?? '',
      searchFields: [
        for (final f in (json['searchFields'] as List? ?? const [])) '$f',
      ],
      groups: [
        for (final g in (json['groups'] as List? ?? const []))
          GroupSpec.fromJson((g as Map).cast<String, Object?>()),
      ],
      aggregations: aggregations,
      offset: (json['offset'] as num?)?.toInt() ?? 0,
      limit: (json['limit'] as num?)?.toInt(),
    );
  }

  @override
  String toString() => 'GridQuery(${toJson()})';
}

/// The answer to a [GridQuery].
class GridResult<T> {
  const GridResult({
    required this.rows,
    required this.totalCount,
    this.groups = const [],
    this.aggregates = const AggregateResult.empty(),
    this.filteredCount,
    this.stats = const {},
  });

  /// The page of data rows, already ordered. Empty when [groups] is used.
  final List<T> rows;

  /// Total rows in the source before filtering, for "x of y" labels.
  final int totalCount;

  /// Rows that matched the filter, before paging. Defaults to [totalCount].
  final int? filteredCount;

  /// The grouped tree, when the query asked for grouping.
  final List<GroupNode<T>> groups;

  /// Grid-wide aggregates for the summary footer.
  final AggregateResult aggregates;

  /// Per-column ranges, keyed by field, for conditional formatting.
  ///
  /// A local source computes these itself, so this is how a remote one makes
  /// data bars and colour scales work at all: without a min and a max there
  /// is nothing to draw a bar against, and a rule over a server-paged column
  /// silently did nothing. A source that returns stats for a column overrides
  /// its own [LatticeDataSource.statsFor] for as long as the result stands.
  final Map<String, ColumnStats> stats;

  int get matchedCount => filteredCount ?? totalCount;

  bool get isGrouped => groups.isNotEmpty;

  bool get isEmpty => rows.isEmpty && groups.isEmpty;

  @override
  String toString() =>
      'GridResult(${rows.length} rows of $matchedCount/$totalCount)';
}

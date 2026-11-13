/// The request a grid makes of its data source.
library;

import 'aggregate.dart';
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

  int get matchedCount => filteredCount ?? totalCount;

  bool get isGrouped => groups.isNotEmpty;

  bool get isEmpty => rows.isEmpty && groups.isEmpty;

  @override
  String toString() =>
      'GridResult(${rows.length} rows of $matchedCount/$totalCount)';
}

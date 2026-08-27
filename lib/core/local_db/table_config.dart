/// Describes how a single PowerSync-synced table maps onto its
/// Supabase/Postgres counterpart, so `Repository<T>` and
/// `SupabaseConnector` don't need per-table special cases hand-written
/// into them.
///
/// Register one of these per table in `table_registry.dart` when you
/// add a new synced table — that's the only place new tables should
/// need touching outside of the actual migration + schema entry.
class TableConfig {
  /// Local PowerSync table name — must match `powersync_schema.dart`.
  final String tableName;

  /// The column Supabase actually uses as primary key for upsert/update/
  /// delete `.eq(...)` calls. Defaults to 'id'. Use this when the local
  /// PowerSync `id` differs from the real PK, e.g. `*_profile` tables,
  /// which use `profile_id` as their real Postgres primary key but still
  /// need a local `id` for PowerSync bookkeeping.
  final String remotePkColumn;

  /// Columns that are `jsonb` in Postgres but travel as JSON-encoded
  /// text through local SQLite. Decoded back to a real Map/List on
  /// upload to Supabase.
  final Set<String> jsonbColumns;

  /// For tables with a composite/synthetic local key (e.g. farmer_crop's
  /// `"$farmerProfileId:$cropId"`), describes how to build the local id
  /// from component values and how to split it back apart for upload.
  /// Leave null for single-column-PK tables.
  final CompositeKey? compositeKey;

  const TableConfig({
    required this.tableName,
    this.remotePkColumn = 'id',
    this.jsonbColumns = const {},
    this.compositeKey,
  });

  bool get hasCompositeKey => compositeKey != null;
}

/// Describes a synthetic composite local id, e.g. farmer_crop's
/// `"<farmerProfileId>:<cropId>"`, and how to turn it back into the
/// real Postgres foreign-key columns for upload.
class CompositeKey {
  /// Ordered list of the real Postgres column names the composite id
  /// is built from, e.g. `['farmer_profile_id', 'crop_id']`.
  final List<String> columns;

  final String separator;

  const CompositeKey(this.columns, {this.separator = ':'});

  /// Builds the local synthetic id from component values, in the same
  /// order as [columns].
  String buildId(List<String> values) {
    assert(values.length == columns.length);
    return values.join(separator);
  }

  /// Splits a local synthetic id back into `{column: value}` pairs,
  /// ready to merge into an upload payload / `.eq()` filters.
  Map<String, String> splitId(String id) {
    final parts = id.split(separator);
    if (parts.length != columns.length) {
      throw FormatException(
        'Invalid composite key for columns $columns: "$id"',
      );
    }
    return Map.fromIterables(columns, parts);
  }
}

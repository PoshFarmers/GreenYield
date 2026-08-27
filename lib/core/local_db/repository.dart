import 'powersync.dart'; // exposes `db`

/// Generic CRUD + watch wrapper over a single PowerSync table, so
/// individual feature services (BuyerProfileService, DriverProfileService,
/// FarmerProfileService, ...) don't each hand-write the same
/// SELECT/INSERT/UPDATE SQL strings.
///
/// [T] is the feature's model type (e.g. BuyerProfile). Supply:
///   - [fromMap]: builds a T from a raw SQLite row
///   - [toInsertMap]: T -> column/value map for INSERT/UPDATE (must NOT
///     include the pk column — that's supplied separately by id)
///
/// This intentionally does NOT read from `table_registry.dart` for pk
/// overrides, since the local `id` column is always what this class
/// filters/writes by — `TableConfig.remotePkColumn` only matters to the
/// connector when pushing to Supabase. Composite-key tables (like
/// farmer_crop) build their local id via `TableConfig.compositeKey`
/// before calling `insert`/`update` here — see FarmerProfileService.
class Repository<T> {
  final String table;
  final T Function(Map<String, dynamic> row) fromMap;
  final Map<String, dynamic> Function(T value) toInsertMap;

  Repository({
    required this.table,
    required this.fromMap,
    required this.toInsertMap,
  });

  /// Watches a single row by local id.
  Stream<T?> watchOne(String id) {
    return db
        .watch('SELECT * FROM $table WHERE id = ?', parameters: [id])
        .map((rows) => rows.isEmpty ? null : fromMap(rows.first));
  }

  /// Watches every row matching an optional WHERE clause. Pass
  /// `where: 'driver_profile_id = ?'` style fragments (no `WHERE`
  /// keyword), with matching positional [parameters].
  Stream<List<T>> watchAll({
    String? where,
    List<Object?> parameters = const [],
    String? orderBy,
    int? limit,
  }) {
    final buffer = StringBuffer('SELECT * FROM $table');
    if (where != null) buffer.write(' WHERE $where');
    if (orderBy != null) buffer.write(' ORDER BY $orderBy');
    if (limit != null) buffer.write(' LIMIT $limit');
    return db
        .watch(buffer.toString(), parameters: parameters)
        .map((rows) => rows.map(fromMap).toList());
  }

  Future<bool> exists(String id) async {
    final row = await db.getOptional('SELECT id FROM $table WHERE id = ?', [
      id,
    ]);
    return row != null;
  }

  Future<T?> getOptional(String id) async {
    final row = await db.getOptional('SELECT * FROM $table WHERE id = ?', [id]);
    return row == null ? null : fromMap(row);
  }

  /// Inserts a new row with a caller-supplied stable [id] — use this for
  /// 1:1 tables where the local id is meaningful (e.g. a `*_profile`
  /// table where id == profile id).
  Future<void> insert(String id, T value) async {
    final map = toInsertMap(value);
    final columns = ['id', ...map.keys];
    final placeholders = List.filled(columns.length, '?').join(', ');
    await db.execute(
      'INSERT INTO $table (${columns.join(', ')}) VALUES ($placeholders)',
      [id, ...map.values],
    );
  }

  /// Inserts a new row with a fresh PowerSync-generated id (`uuid()`),
  /// for tables where the local id is a synthetic key rather than a
  /// caller-supplied stable one (e.g. `vehicle`, `profile_role`).
  Future<void> insertGenerated(T value) async {
    final map = toInsertMap(value);
    final columns = map.keys.join(', ');
    final placeholders = map.keys.map((_) => '?').join(', ');
    await db.execute(
      'INSERT INTO $table (id, $columns) VALUES (uuid(), $placeholders)',
      map.values.toList(),
    );
  }

  /// Updates an existing row by local [id].
  Future<void> update(String id, T value) async {
    final map = toInsertMap(value);
    final setClause = map.keys.map((k) => '$k = ?').join(', ');
    await db.execute('UPDATE $table SET $setClause WHERE id = ?', [
      ...map.values,
      id,
    ]);
  }

  Future<void> delete(String id) async {
    await db.execute('DELETE FROM $table WHERE id = ?', [id]);
  }
}

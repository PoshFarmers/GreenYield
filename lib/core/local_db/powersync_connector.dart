import 'dart:convert';

import 'package:powersync/powersync.dart';

import '../supabase/client.dart';

/// Tables whose real Supabase primary key column differs from the
/// local `id` PowerSync uses internally.
const _pkColumnOverrides = {
  'farmer_profile': 'profile_id',
  'buyer_profile': 'profile_id',
  'driver_profile': 'profile_id',
};

/// Columns that are `jsonb` in Postgres but are stored as JSON-encoded
/// text locally (SQLite/PowerSync has no native object column type).
const _jsonbColumns = {
  'profile': {'address'},
};

class SupabaseConnector extends PowerSyncBackendConnector {
  @override
  Future<PowerSyncCredentials?> fetchCredentials() async {
    final session = supabase.auth.currentSession;
    if (session == null) return null;
    return PowerSyncCredentials(
      endpoint: 'https://6a8aec61a77ca1231d221bdb.powersync.journeyapps.com',
      token: session.accessToken,
    );
  }

  @override
  Future<void> uploadData(PowerSyncDatabase database) async {
    final transaction = await database.getNextCrudTransaction();
    if (transaction == null) return;

    for (final op in transaction.crud) {
      final table = supabase.from(op.table);
      final pkColumn = _pkColumnOverrides[op.table] ?? 'id';
      final opData = _decodeJsonbColumns(op.table, op.opData);

      switch (op.op) {
        case UpdateType.put:
          await table.upsert({pkColumn: op.id, ...?opData});
        case UpdateType.patch:
          await table.update(opData!).eq(pkColumn, op.id);
        case UpdateType.delete:
          await table.delete().eq(pkColumn, op.id);
      }
    }
    await transaction.complete();
  }

  /// Decodes any column listed in [_jsonbColumns] for [table] from its
  /// locally-stored JSON string back into a real Map/List, so Supabase
  /// writes it into the jsonb column as an object rather than a string.
  Map<String, dynamic>? _decodeJsonbColumns(
    String table,
    Map<String, dynamic>? data,
  ) {
    if (data == null) return null;
    final cols = _jsonbColumns[table];
    if (cols == null) return data;

    final result = Map<String, dynamic>.from(data);
    for (final col in cols) {
      final value = result[col];
      if (value is String) {
        result[col] = jsonDecode(value);
      }
    }
    return result;
  }
}

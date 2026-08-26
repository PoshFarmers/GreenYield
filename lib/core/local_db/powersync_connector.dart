import 'dart:convert';

import 'package:powersync/powersync.dart';

import '../supabase/client.dart';
import 'table_registry.dart';

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
      final config = configFor(op.table);
      final table = supabase.from(config.tableName);
      final opData = _decodeJsonbColumns(config, op.opData);

      if (config.hasCompositeKey) {
        await _uploadCompositeKeyRow(table, config, op, opData);
        continue;
      }

      switch (op.op) {
        case UpdateType.put:
          await table.upsert({config.remotePkColumn: op.id, ...?opData});
        case UpdateType.patch:
          await table.update(opData!).eq(config.remotePkColumn, op.id);
        case UpdateType.delete:
          await table.delete().eq(config.remotePkColumn, op.id);
      }
    }
    await transaction.complete();
  }

  /// Handles any table registered with a [CompositeKey] generically —
  /// e.g. farmer_crop's `"<farmerProfileId>:<cropId>"` local id. Adding
  /// a second composite-key table (an order_item, a delivery_stop, ...)
  /// only needs a `TableConfig(compositeKey: ...)` entry in the
  /// registry — no new branch here, unlike the old `_uploadFarmerCrop`.
  Future<void> _uploadCompositeKeyRow(
    dynamic table,
    TableConfig config,
    dynamic op,
    Map<String, dynamic>? opData,
  ) async {
    final keyColumns = config.compositeKey!.splitId(op.id);

    switch (op.op) {
      case UpdateType.put:
        await table.upsert({...keyColumns, ...?opData});
      case UpdateType.patch:
        var query = table.update(opData!);
        for (final entry in keyColumns.entries) {
          query = query.eq(entry.key, entry.value);
        }
        await query;
      case UpdateType.delete:
        var query = table.delete();
        for (final entry in keyColumns.entries) {
          query = query.eq(entry.key, entry.value);
        }
        await query;
    }
  }

  /// Decodes any column listed as jsonb in [config] from its locally
  /// stored JSON string back into a real Map/List, so Supabase writes
  /// it into the jsonb column as an object rather than a string.
  Map<String, dynamic>? _decodeJsonbColumns(
    TableConfig config,
    Map<String, dynamic>? data,
  ) {
    if (data == null || config.jsonbColumns.isEmpty) return data;

    final result = Map<String, dynamic>.from(data);
    for (final col in config.jsonbColumns) {
      final value = result[col];
      if (value is String) {
        result[col] = jsonDecode(value);
      }
    }
    return result;
  }
}

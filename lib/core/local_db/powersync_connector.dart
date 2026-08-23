import 'package:powersync/powersync.dart';

import '../supabase/client.dart';

/// Tables whose real Supabase primary key column differs from the
/// local `id` PowerSync uses internally.
const _pkColumnOverrides = {
  'farmer_profile': 'profile_id',
  'buyer_profile': 'profile_id',
  'driver_profile': 'profile_id',
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

      switch (op.op) {
        case UpdateType.put:
          await table.upsert({pkColumn: op.id, ...?op.opData});
        case UpdateType.patch:
          await table.update(op.opData!).eq(pkColumn, op.id);
        case UpdateType.delete:
          await table.delete().eq(pkColumn, op.id);
      }
    }
    await transaction.complete();
  }
}

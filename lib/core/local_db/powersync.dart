import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:powersync/powersync.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'powersync_schema.dart';
import 'powersync_connector.dart';
import '../supabase/client.dart';

late final PowerSyncDatabase db;

Future<void> initPowerSync() async {
  final dir = await getApplicationSupportDirectory();
  final dbPath = p.join(dir.path, 'greenyield.db');

  db = PowerSyncDatabase(schema: schema, path: dbPath);
  await db.initialize();

  if (supabase.auth.currentSession != null) {
    await db.connect(connector: SupabaseConnector());
  }

  supabase.auth.onAuthStateChange.listen((state) async {
    switch (state.event) {
      case AuthChangeEvent.signedIn:
      case AuthChangeEvent.tokenRefreshed:
        await db.connect(connector: SupabaseConnector());
      case AuthChangeEvent.signedOut:
        await db.disconnectAndClear();
      default:
        break;
    }
  });
}

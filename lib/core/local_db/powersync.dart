import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:powersync/powersync.dart';

import 'powersync_schema.dart';
import 'powersync_connector.dart';

late final PowerSyncDatabase db;

Future<void> initPowerSync() async {
  final dir = await getApplicationSupportDirectory();
  final dbPath = p.join(dir.path, 'greenyield.db');

  db = PowerSyncDatabase(schema: schema, path: dbPath);
  await db.initialize();
  await db.connect(connector: SupabaseConnector());
}

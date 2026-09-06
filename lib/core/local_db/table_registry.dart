import 'table_config.dart';

export 'table_config.dart';

/// Central registry of [TableConfig] for every PowerSync-synced table.
///
/// This is the *one* place a new table's local-vs-remote quirks (real
/// PK column, jsonb columns, composite keys) need to be declared.
/// `Repository<T>` and `SupabaseConnector.uploadData()` both read from
/// here instead of hand-checking table names — so growing the schema
/// (marketplace, orders, delivery, wallet, ...) doesn't mean editing
/// the connector again.
final Map<String, TableConfig> tableRegistry = {
  'profile': const TableConfig(tableName: 'profile', jsonbColumns: {'address'}),
  'profile_role': const TableConfig(tableName: 'profile_role'),
  'farmer_profile': const TableConfig(
    tableName: 'farmer_profile',
    remotePkColumn: 'profile_id',
  ),
  'farmer_crop': const TableConfig(
    tableName: 'farmer_crop',
    compositeKey: CompositeKey(['farmer_profile_id', 'crop_id']),
  ),
  'crop': const TableConfig(tableName: 'crop'),
  'produce_listing': const TableConfig(tableName: 'produce_listing'),
  'buyer_profile': const TableConfig(
    tableName: 'buyer_profile',
    remotePkColumn: 'profile_id',
  ),
  'driver_profile': const TableConfig(
    tableName: 'driver_profile',
    remotePkColumn: 'profile_id',
  ),
  'vehicle': const TableConfig(tableName: 'vehicle'),
  'driver_route_preference': const TableConfig(
    tableName: 'driver_route_preference',
  ),
  'cart': const TableConfig(tableName: 'cart'),
  'cart_item': const TableConfig(tableName: 'cart_item'),
  'notification': const TableConfig(
    tableName: 'notification',
    jsonbColumns: {'payload'},
  ),

  // --- Sprint 2 / Task 3.2 — Order Creation & Checkout Flow ---
  'orders': const TableConfig(
    tableName: 'orders',
    jsonbColumns: {'delivery_address'},
  ),
  'order_item': const TableConfig(tableName: 'order_item'),
  'payment': const TableConfig(tableName: 'payment'),

  // --- add new tables here as delivery/wallet land ---
  // 'listing': TableConfig(tableName: 'listing', remotePkColumn: 'id'),
};

TableConfig configFor(String table) {
  final config = tableRegistry[table];
  if (config == null) {
    throw StateError(
      'No TableConfig registered for "$table" — add one to table_registry.dart',
    );
  }
  return config;
}

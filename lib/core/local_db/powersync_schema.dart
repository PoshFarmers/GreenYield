import 'package:powersync/powersync.dart';

const schema = Schema([
  Table('profile', [
    Column.text('first_name'),
    Column.text('last_name'),
    Column.text('address'),
    Column.text('phone'),
    Column.text('avatar_url'),
    Column.text('preferred_language'),
    Column.text('active_role'),
    Column.text('location_text'),
    Column.text('location_geojson'),
    Column.text('location_point'),
    Column.text('created_at'),
  ]),
  Table('profile_role', [Column.text('profile_id'), Column.text('role')]),
  Table('farmer_profile', [Column.text('profile_id')]),
  Table('farmer_crop', [
    Column.text('farmer_profile_id'),
    Column.text('crop_id'),
    Column.text('description'),
    Column.real('default_price_per_kg'),
    Column.text('image_url'),
  ]),
  Table('crop', [Column.text('name'), Column.text('category')]),
  // `status` is a Postgres enum, so only its `status_text` mirror is
  // synced (see the powersync_compat_view migration).
  Table('produce_listing', [
    Column.text('farmer_profile_id'),
    Column.text('crop_id'),
    Column.real('price_per_kg'),
    Column.real('available_quantity_kg'),
    Column.text('status_text'),
    Column.text('description'),
    Column.text('image_url'),
    Column.text('harvested_on'),
    Column.text('published_at'),
    Column.text('expires_at'),
  ]),
  Table('buyer_profile', [
    Column.text('profile_id'),
    Column.text('buyer_type'),
    Column.text('buyer_label'),
  ]),
  Table('driver_profile', [Column.text('profile_id')]),
  Table('vehicle', [
    Column.text('driver_profile_id'),
    Column.text('vehicle_type'),
    Column.text('plate_number'),
    Column.real('max_load_kg'),
    Column.real('preferred_min_load_kg'),
  ]),
  Table('driver_route_preference', [
    Column.text('driver_profile_id'),
    Column.text('origin_location'),
    Column.text('destination_location'),
    Column.text('direction'), // outbound|return|both
    Column.integer('active_days'), // bitmask, bit0=Mon .. bit6=Sun
    Column.integer('is_active'), // 0/1 — PowerSync has no bool column
  ]),
  Table('notification', [
    Column.text('profile_id'),
    Column.text('type'),
    Column.text('title'),
    Column.text('body'),
    Column.text('payload'),
    Column.text('source_table'),
    Column.text('source_id'),
    Column.text('read_at'),
    Column.text('created_at'),
  ]),
  Table('cart', [
    Column.text('buyer_profile_id'),
    Column.text('created_at'),
    Column.text('updated_at'),
  ]),
  Table('cart_item', [
    Column.text('cart_id'),
    Column.text('produce_listing_id'),
    Column.real('quantity_kg'),
    Column.text('created_at'),
    Column.text('updated_at'),
  ]),
  // market_price and price_trend are keyed by crop_id in Postgres (no
  // separate `id` column there) — the PowerSync sync-rules stream
  // aliases crop_id AS id for both. See the sync-rules note in this
  // branch's instructions if that alias isn't in place yet.
  Table('market_price', [
    Column.text('crop_id'),
    Column.real('avg_price_per_kg'),
    Column.real('min_price_per_kg'),
    Column.real('max_price_per_kg'),
    Column.text('as_of_date'),
    Column.text('updated_at'),
  ]),
  Table('price_trend', [
    Column.text('crop_id'),
    Column.text('trend_direction'), // 'up' | 'down' | 'stable'
    Column.real('change_percent'),
    Column.integer('period_days'),
    Column.text('computed_at'),
  ]),
  // price_history has a real `id` PK in Postgres already, so no id
  // aliasing needed in the sync-rules stream (`price_history_recent`
  // already does a plain `SELECT * FROM price_history`).
  Table('price_history', [
    Column.text('crop_id'),
    Column.text('price_date'),
    Column.real('avg_price_per_kg'),
    Column.real('min_price_per_kg'),
    Column.real('max_price_per_kg'),
    Column.integer('order_count'),
    Column.text('created_at'),
  ]),
]);

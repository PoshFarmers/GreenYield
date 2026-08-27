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
  ]),
  Table('profile_role', [Column.text('profile_id'), Column.text('role')]),
  Table('farmer_profile', [Column.text('profile_id')]),
  Table('farmer_crop', [
    Column.text('farmer_profile_id'),
    Column.text('crop_id'),
  ]),
  Table('crop', [Column.text('name'), Column.text('category')]),
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
  ]),
]);

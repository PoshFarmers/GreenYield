import 'dart:async';

import '../../../core/local_db/powersync.dart'; // exposes `db`
import '../../../core/local_db/repository.dart';
import '../../../models/driver_profile.dart';

class DriverProfileService {
  final _vehicles = Repository<Vehicle>(
    table: 'vehicle',
    fromMap: Vehicle.fromMap,
    toInsertMap: (v) => v.toInsertMap(),
  );

  final _routes = Repository<RoutePreference>(
    table: 'driver_route_preference',
    fromMap: RoutePreference.fromMap,
    toInsertMap: (r) => r.toInsertMap(),
  );

  Future<bool> hasProfile(String profileId) async {
    final row = await db.getOptional(
      'SELECT id FROM driver_profile WHERE profile_id = ?',
      [profileId],
    );
    return row != null;
  }

  Stream<DriverProfile?> watchOwnProfile(String profileId) {
    final vehicleStream = _vehicles.watchAll(
      where: 'driver_profile_id = ?',
      parameters: [profileId],
      orderBy: 'id',
      limit: 1,
    );
    final routeStream = watchRoutes(profileId);

    // No rxdart in this project, so hand-roll a combineLatest: cache the
    // most recent value from each source stream and re-emit a merged
    // DriverProfile whenever either one fires.
    late final StreamController<DriverProfile?> controller;
    List<Vehicle>? lastVehicles;
    List<RoutePreference>? lastRoutes;
    StreamSubscription<List<Vehicle>>? vehicleSub;
    StreamSubscription<List<RoutePreference>>? routeSub;

    void emit() {
      if (lastVehicles == null || lastRoutes == null) return;
      controller.add(
        DriverProfile(
          profileId: profileId,
          primaryVehicle: lastVehicles!.isEmpty ? null : lastVehicles!.first,
          routePreferences: lastRoutes!,
        ),
      );
    }

    controller = StreamController<DriverProfile?>(
      onListen: () {
        vehicleSub = vehicleStream.listen(
          (v) {
            lastVehicles = v;
            emit();
          },
          onError: controller.addError,
        );
        routeSub = routeStream.listen(
          (r) {
            lastRoutes = r;
            emit();
          },
          onError: controller.addError,
        );
      },
      onCancel: () async {
        await vehicleSub?.cancel();
        await routeSub?.cancel();
      },
    );
    return controller.stream;
  }

  /// Watches every saved preferred route for [profileId], most recently
  /// added first.
  Stream<List<RoutePreference>> watchRoutes(String profileId) {
    return _routes.watchAll(
      where: 'driver_profile_id = ?',
      parameters: [profileId],
      orderBy: 'id',
    );
  }

  /// driver_profile is a marker row (profile_id only, no other columns
  /// worth modeling) — not worth a full `Repository<T>`, so it stays a
  /// direct db call, same as before.
  /// [routes] is optional — preferred routes are skippable during setup
  /// and can always be added later from the profile screen.
  Future<void> createProfile(
    String profileId,
    Vehicle vehicle, {
    List<RoutePreference> routes = const [],
  }) async {
    await db.execute(
      'INSERT INTO driver_profile (id, profile_id) VALUES (?, ?)',
      [profileId, profileId],
    );
    await _vehicles.insertGenerated(vehicle);
    for (final route in routes) {
      await _routes.insertGenerated(route);
    }
  }

  Future<void> addVehicle(Vehicle vehicle) =>
      _vehicles.insertGenerated(vehicle);

  Future<void> updateVehicle(String vehicleId, Vehicle vehicle) =>
      _vehicles.update(vehicleId, vehicle);

  Future<void> addRoute(RoutePreference route) =>
      _routes.insertGenerated(route);

  Future<void> updateRoute(String routeId, RoutePreference route) =>
      _routes.update(routeId, route);

  Future<void> deleteRoute(String routeId) => _routes.delete(routeId);

  Future<void> setRouteActive(RoutePreference route, bool isActive) =>
      _routes.update(route.id!, route.copyWith(isActive: isActive));
}

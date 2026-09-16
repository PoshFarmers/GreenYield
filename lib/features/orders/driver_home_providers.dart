import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/driver_stop.dart';
import 'driver_home_service.dart';

final _driverHomeService = const DriverHomeService();

/// Today's pickup/dropoff stops for [driverProfileId]. Re-fetch after
/// any pickup/dropoff/start action via `ref.invalidate`.
final driverTodayStopsProvider = FutureProvider.autoDispose
    .family<List<DriverStop>, String>((ref, driverProfileId) {
      return _driverHomeService.fetchTodayStops(driverProfileId);
    });

/// Whether the driver has tapped "Start Route" today. Persisted so the
/// button stays flipped if the app is backgrounded/reopened, and keyed
/// per-day so it resets tomorrow.
class DriverShiftStartedNotifier extends Notifier<bool> {
  String get _prefsKey {
    final today = DateTime.now();
    final ymd =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    return 'driver_shift_started_$ymd';
  }

  @override
  bool build() {
    _load();
    return false;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_prefsKey) ?? false;
  }

  Future<void> markStarted() async {
    state = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, true);
  }
}

final driverShiftStartedProvider =
    NotifierProvider<DriverShiftStartedNotifier, bool>(
      DriverShiftStartedNotifier.new,
    );

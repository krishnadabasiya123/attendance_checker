import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:attendance_system/Model/location_point.dart';
import 'package:attendance_system/repository/location_repository.dart';
import 'package:attendance_system/utiils/hive_utils.dart';
import 'package:attendance_system/utiils/util.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

class LocationTracker {
  LocationTracker._();
  static final LocationTracker instance = LocationTracker._();

  StreamSubscription<Position>? _positionSubscription;
  Timer? _heartbeatTimer;
  Timer? _mockLocationTimer;
  bool _isRunning = false;
  bool _isSyncing = false;

  double? _lastSavedLat;
  double? _lastSavedLon;
  DateTime? _lastSavedTimestamp; // GPS satellite time — not phone/server clock

  DateTime? _lastSyncTime;
  int _syncIntervalMinutes = 1;

  bool get isRunning => _isRunning;

  // ---------------------------------------------------------------------------
  // START
  // ---------------------------------------------------------------------------

  Future<void> start() async {
    if (_isRunning) {
      if (kDebugMode) print('📍 TRACKER: Already running.');
      return;
    }

    await HiveUtils.openBox();

    _isRunning = true;
    _lastSavedLat = null;
    _lastSavedLon = null;
    _lastSavedTimestamp = null;
    _lastSyncTime = DateTime.now();

    _syncIntervalMinutes = locationUpdateInterval;
    if (_syncIntervalMinutes <= 0) _syncIntervalMinutes = 1;

    late LocationSettings locationSettings;

    if (Platform.isAndroid) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,

        // 15m: fine enough to capture walking turns in a market,
        // dense enough to trace highway curves at 80 km/h.
        distanceFilter: 15,

        // 10s: balanced for battery life on budget phones (Tecno, Infinix).
        // Aggressive 5s intervals drain battery and cause thermal issues
        // on low-end hardware common in India and East Africa.
        intervalDuration: const Duration(seconds: 10),

        // ── TOWER JUMP PREVENTION — THE CORE SETTING ────────────────────────
        // forceLocationManager: true
        //
        // Forces Android to read from the hardware GPS chip ONLY.
        // This completely disables the Fused Location Provider, which is
        // the source of ALL cell tower jumps. When this is true:
        //   • GPS satellites  → allowed in  ✅
        //   • Cell towers     → blocked out ❌
        //   • Wi-Fi position  → blocked out ❌
        //
        // If GPS ha s no signal (user is indoors), we simply get no point.
        // A gap in the route is honest. A tower jump is a lie.
        // ────────────────────────────────────────────────────────────────────
        forceLocationManager: true,

        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText: 'Tracking your shift location',
          notificationTitle: 'Omkar - Shift Active',
          notificationChannelName: 'Location Tracking',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    } else if (Platform.isIOS || Platform.isMacOS) {
      // iOS does not expose forceLocationManager.
      // However, bestForNavigation + automotiveNavigation activity type keeps
      // iOS strongly GPS-first and minimises tower fallback.
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        activityType: ActivityType.automotiveNavigation,
        distanceFilter: 15,
        showBackgroundLocationIndicator: true,
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 15,
      );
    }

    _positionSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          _processLocation,
          onError: (Object? error) {
            if (kDebugMode) print('❌ TRACKER: Stream error: $error');
          },
        );

    // Heartbeat every 30s handles the stationary salesman case.
    // (User stopped at a shop — no movement, but we still need to sync.)
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkSyncDue(),
    );

    //_startMockLocationTimer();

    if (kDebugMode) {
      print('✅ TRACKER: Started — GPS satellites only, zero tower jumps.');
    }
  }

  // ---------------------------------------------------------------------------
  // STOP
  // ---------------------------------------------------------------------------

  Future<void> stop() async {
    try {
      await _positionSubscription?.cancel();
      _heartbeatTimer?.cancel();
      _mockLocationTimer?.cancel();
    } catch (e) {
      if (kDebugMode) print('❌ TRACKER: Error on stop: $e');
    }
    _positionSubscription = null;
    _heartbeatTimer = null;
    _mockLocationTimer = null;
    _isRunning = false;
    _lastSyncTime = null;
    if (kDebugMode) print('🛑 TRACKER: Stopped.');
  }

  // ---------------------------------------------------------------------------
  // UPDATE INTERVAL (called when admin changes config)
  // ---------------------------------------------------------------------------

  void updateInterval(int newIntervalMinutes) {
    final oldInterval = _syncIntervalMinutes;
    _syncIntervalMinutes = newIntervalMinutes > 0 ? newIntervalMinutes : 1;
    if (kDebugMode) {
      print('⚙️ TRACKER: Sync interval → $_syncIntervalMinutes min');
    }
    if (_isRunning && _syncIntervalMinutes < oldInterval) {
      _checkSyncDue();
    }
  }

  // ---------------------------------------------------------------------------
  // PROCESS LOCATION
  // ---------------------------------------------------------------------------

  Future<void> _processLocation(Position position) async {
    // ── GATE 1: ACCURACY — Universal 35m Standard ───────────────────────────
    // In every country worldwide:
    //   Satellite fix (real GPS) → 5m – 35m   ✅ accepted
    //   Cell tower guess         → 50m – 5000m ❌ rejected
    //
    // forceLocationManager already blocks tower data at hardware level.
    // This gate is the final software safety net for any edge case.
    if (position.accuracy > 35) {
      if (kDebugMode) {
        print(
          '❌ REJECTED (accuracy) '
          '${position.accuracy.toStringAsFixed(1)}m > 35m',
        );
      }
      return;
    }

    // ── GATE 2: STALE DATA — Budget Phone Protection ────────────────────────
    // Budget phones (Tecno, Infinix, older Samsung) take 30–50s to get a
    // fresh GPS fix after waking from Android doze/sleep mode.
    // During that wake-up period, Android sometimes delivers the last cached
    // GPS point, which could be from minutes ago.
    // 60s rejects these stale cached points while accepting all real fixes,
    // even on the slowest GPS chip.
    final ageSeconds = DateTime.now()
        .difference(position.timestamp)
        .inSeconds
        .abs(); // abs() guards against minor GPS/system clock skew
    if (ageSeconds > 60) {
      if (kDebugMode) {
        print('❌ REJECTED (stale) ${ageSeconds}s > 60s');
      }
      return;
    }

    // ── GATE 3: MOVEMENT + SPEED — Physics-Based Global Rule ────────────────
    if (_lastSavedLat != null &&
        _lastSavedLon != null &&
        _lastSavedTimestamp != null) {
      final distance = Geolocator.distanceBetween(
        _lastSavedLat!,
        _lastSavedLon!,
        position.latitude,
        position.longitude,
      );

      // Use GPS satellite timestamp — NOT phone clock or server time.
      // Satellite time is accurate across all time zones and works correctly
      // even when the user has no internet or crosses a country border.
      final timeDiffSeconds = position.timestamp
          .difference(_lastSavedTimestamp!)
          .inSeconds
          .abs(); // abs() prevents negative values from GPS clock drift

      // Duplicate timestamp — skip
      if (timeDiffSeconds < 1) {
        if (kDebugMode) print('⚠️ TRACKER: Duplicate timestamp — skipped.');
        return;
      }

      // GPS jitter while standing still — not real movement
      if (distance < 10) {
        if (kDebugMode) {
          print('📍 TRACKER: No movement — ${distance.toStringAsFixed(1)}m');
        }
        return;
      }

      // Speed gate — 45 m/s = 162 km/h
      // Physics of road vehicles is the same in every country:
      //   Walking salesman  :  1.4 m/s  (5 km/h)
      //   Boda-boda/motorcycle: 25 m/s  (90 km/h)
      //   Matatu / minibus  :  33 m/s   (120 km/h)
      //   Car on highway    :  39 m/s   (140 km/h)
      // 45 m/s gives safe margin above the fastest realistic vehicle.
      // A real tower jump = 500 – 50,000 m/s → always caught here.
      final speedMps = distance / timeDiffSeconds;
      if (speedMps > 45) {
        if (kDebugMode) {
          print(
            '❌ REJECTED (speed) '
            '${(speedMps * 3.6).toStringAsFixed(0)} km/h '
            '(${distance.toStringAsFixed(0)}m in ${timeDiffSeconds}s)',
          );
        }
        return;
      }
    }

    // ── ACCEPTED — SAVE ──────────────────────────────────────────────────────
    _lastSavedLat = position.latitude;
    _lastSavedLon = position.longitude;
    _lastSavedTimestamp = position.timestamp; // GPS satellite time
    final point = LocationPoint(
      latitude: position.latitude,
      longitude: position.longitude,
      speed: position.speed,
      timestamp: position.timestamp, // GPS satellite time — timezone safe
      date: todayStr,
    );

    final repo = LocationRepository();
    await repo.saveLocal(point);

    if (kDebugMode) {
      print(
        '✅ SAVED (${position.accuracy.toStringAsFixed(1)}m) '
        '${position.latitude.toStringAsFixed(6)}, '
        '${position.longitude.toStringAsFixed(6)} '
        '@ ${(position.speed * 3.6).toStringAsFixed(0)} km/h',
      );
    }

    // ── SYNC TRIGGERS ────────────────────────────────────────────────────────

    // Flush every 100 points (~1.5 km at 15m spacing).
    // Small frequent batches give the server accurate spread-out timestamps.
    // Large batches (1000 points) cause all points to arrive at once,
    // making the map show many dots at the same timestamp — a display bug.
    final count = repo.getCount();
    if (count >= 1000) {
      if (kDebugMode) print('🔔 TRACKER: 100 points — syncing.');
      await syncToServer();
      _lastSyncTime = DateTime.now();
      return;
    }

    // Time-based sync.
    // Fallback = 1 hour ago so the very first sync always triggers correctly.
    // (If fallback were DateTime.now(), elapsed = 0 and first sync would skip.)
    final elapsed = DateTime.now().difference(
      _lastSyncTime ?? DateTime.now().subtract(const Duration(hours: 1)),
    );
    if (elapsed.inSeconds >= (_syncIntervalMinutes * 60)) {
      if (kDebugMode) print('🔔 TRACKER: Time interval reached — syncing.');
      await syncToServer();
      _lastSyncTime = DateTime.now();
    }
  }

  // ---------------------------------------------------------------------------
  // HEARTBEAT — fires every 60s
  // Handles the stationary salesman case (stopped at a shop or customer).
  // ---------------------------------------------------------------------------

  Future<void> _checkSyncDue() async {
    if (!_isRunning || _isSyncing) return;

    final elapsed = DateTime.now().difference(
      _lastSyncTime ?? DateTime.now().subtract(const Duration(hours: 1)),
    );

    if (elapsed.inSeconds < (_syncIntervalMinutes * 60)) return;

    if (kDebugMode)
      print('⏰ HEARTBEAT: ${elapsed.inSeconds}s since last sync.');

    final repo = LocationRepository();

    if (repo.getCount() > 0) {
      // Points buffered — flush them
      await syncToServer();
      _lastSyncTime = DateTime.now();
      return;
    }

    // No movement — request one fresh GPS fix to record current position
    if (kDebugMode) print('📍 HEARTBEAT: Stationary — requesting GPS fix.');

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: Platform.isAndroid
            ? AndroidSettings(
                accuracy: LocationAccuracy.bestForNavigation,
                forceLocationManager: true, // GPS satellites only here too
              )
            : const LocationSettings(
                accuracy: LocationAccuracy.bestForNavigation,
              ),
      );

      if (position.accuracy <= 35) {
        await _processLocation(position);
      } else if (kDebugMode) {
        print(
          '⚠️ HEARTBEAT: Inaccurate fix '
          '(${position.accuracy.toStringAsFixed(1)}m) — skipping.',
        );
      }
    } catch (e) {
      if (kDebugMode) print('❌ HEARTBEAT: Failed: $e');
    }
  }

  Future<void> syncToServer() async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      if (kDebugMode) print('☁️ TRACKER: Syncing to server...');
      final repo = LocationRepository();
      final String todayDateStr = DateFormat(
        'dd-MM-yyyy',
      ).format(DateTime.now());
      await repo.syncLocationsToServer(date: todayDateStr);
    } catch (e) {
      if (kDebugMode) print('❌ Sync error: $e');
    } finally {
      _isSyncing = false;
    }
  }
}

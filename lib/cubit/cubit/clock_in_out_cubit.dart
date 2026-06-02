import 'dart:developer';

import 'package:attendance_system/repository/clock_in_out_repository.dart';
import 'package:attendance_system/utiils/util.dart';
import 'package:bloc/bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../utiils/hive_constant.dart';
import 'package:geolocator/geolocator.dart';
import 'package:attendance_system/service/location_service.dart';
import 'package:attendance_system/service/background_sync_service.dart';
import 'package:attendance_system/service/manual_sync_service.dart';

@immutable
sealed class ClockInOutState {}

final class ClockInOutInitial extends ClockInOutState {}

final class ClockInOutLoading extends ClockInOutState {}

final class ClockInOutSuccess extends ClockInOutState {
  final bool isClockedIn;
  ClockInOutSuccess({required this.isClockedIn});
}

final class ClockInOutError extends ClockInOutState {
  final String message;
  ClockInOutError({required this.message});
}

class ClockInOutCubit extends Cubit<ClockInOutState> {
  ClockInOutCubit() : super(ClockInOutInitial());

  final ClockInOutRepository _repository = ClockInOutRepository();

  bool isClockIn = false;

  // in hive clockInOutBox has is_clocked_in key
  void loadClockStatus() {
    emit(ClockInOutLoading());
    try {
      final box = Hive.box<dynamic>(clockInOutDataBox);
      final isClockedIn =
          box.get(clockInStatusKey, defaultValue: false) as bool;
      isClockIn = isClockedIn;

      emit(ClockInOutSuccess(isClockedIn: isClockedIn));
    } catch (e) {
      emit(
        ClockInOutError(
          message: "Failed to load clock status: ${e.toString()}",
        ),
      );
    }
  }

  Future<Map<String, String>?> _getCurrentLocation() async {
    try {
      if (kDebugMode) {
        log('📍 Getting current location (with 10s timeout)...');
      }

      // WRAP IN STRICT TIMEOUT because Geolocator can hang on Simulator
      return await Future<Map<String, String>?>.delayed(
        Duration.zero,
        () async {
          try {
            // Check permission
            final permission = await Geolocator.checkPermission();
            if (permission == LocationPermission.denied ||
                permission == LocationPermission.deniedForever) {
              if (kDebugMode) {
                log('⚠️ Permission denied regarding current location fetch.');
              }
              return null;
            }

            final position = await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.high,
              ),
            );

            if (kDebugMode) {
              log(
                '📍 Got position: ${position.latitude}, ${position.longitude}',
              );
            }
            return {
              'latitude': position.latitude.toString(),
              'longitude': position.longitude.toString(),
            };
          } catch (e) {
            rethrow;
          }
        },
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          if (kDebugMode) {
            log(
              '❌ STRICT TIMEOUT REACHED (10s). Returning null to unblock UI.',
            );
          }
          return null;
        },
      );
    } catch (e) {
      if (kDebugMode) {
        log('❌ Exception in _getCurrentLocation: $e');
      }
      return null;
    }
  }

  Future<void> setClockInOut({required bool isClockIn}) async {
    if (isClockIn) {
      await clockOut();
    } else {
      await clockIn();
    }
  }

  Future<void> clockOut() async {
    emit(ClockInOutLoading());
    try {
      final currentLocation = await _getCurrentLocation();
      if (currentLocation == null) {
        throw Exception('Failed to get current location');
      }

      await LocationTracker.instance.stop();

      final int outTime = DateTime.now().millisecondsSinceEpoch;
      final outEntry = {
        "type": "out",
        "time": outTime,
        "lat": currentLocation["latitude"],
        "long": currentLocation["longitude"],
        "isSync": false,
      };

      final box = Hive.box<dynamic>(clockInOutDataBox);

      // Determine the correct date key to append the clock-out entry to.
      // If the corresponding clock-in was on a previous date (rollover shift),
      // we must append this clock-out to that previous date's key so they remain paired.
      String targetDateKey = todayStr;

      // Find all Hive keys matching date format (dd-MM-yyyy)
      final dateKeys = box.keys.where((key) {
        if (key is! String) return false;
        final parts = key.split('-');
        return parts.length == 3 && parts.every((p) => int.tryParse(p) != null);
      }).toList();

      final List<Map<String, dynamic>> allEntriesWithDate = [];
      for (final dateKey in dateKeys) {
        final list = box.get(dateKey);
        if (list is List) {
          for (final item in list) {
            if (item is Map) {
              allEntriesWithDate.add({
                'dateKey': dateKey,
                'entry': Map<String, dynamic>.from(item),
              });
            }
          }
        }
      }

      if (allEntriesWithDate.isNotEmpty) {
        // Sort chronologically by entry time
        allEntriesWithDate.sort((a, b) {
          final timeA = (a['entry'] as Map)['time'] as int? ?? 0;
          final timeB = (b['entry'] as Map)['time'] as int? ?? 0;
          return timeA.compareTo(timeB);
        });

        // The last entry in chronological order is the active clock-in
        final lastItem = allEntriesWithDate.last;
        final lastType = (lastItem['entry'] as Map)['type'] as String?;
        if (lastType == 'in') {
          targetDateKey = lastItem['dateKey'] as String;
        }
      }

      // Append the out entry to Hive under the target date list
      final List<dynamic> existingEntries = List<dynamic>.from(
        box.get(targetDateKey) ?? [],
      );
      existingEntries.add(outEntry);
      await box.put(targetDateKey, existingEntries);

      // Mark the global clocked in status to false and reload states
      await box.put(clockInStatusKey, false);
      isClockIn = false;
      ManualSyncService.instance.forceManualSync();
      // Emit success state immediately to stop the button loading state instantly
      emit(ClockInOutSuccess(isClockedIn: isClockIn));

      // Trigger the manual sync process asynchronously in the background without blocking the UI
    } catch (e) {
      emit(ClockInOutError(message: e.toString()));
    }
  }

  Future<void> clockIn() async {
    emit(ClockInOutLoading());
    try {
      final currentLocation = await _getCurrentLocation();
      if (currentLocation == null) {
        throw Exception('Failed to get current location');
      }
      final entry = {
        "type": "in",
        "time": timestamp,
        "lat": currentLocation["latitude"],
        "long": currentLocation["longitude"],
      };

      await _repository.setClockInOut(date: todayStr, entry: entry);

      // Clean completed historical dates immediately on new clock-in (handles offline)
      await BackgroundSyncService.instance.cleanCompletedDates();

      // await LocationTracker.instance.start();
      if (!LocationTracker.instance.isRunning) {
        if (kDebugMode) {
          print('🚀 CUBIT: Starting location tracking');
        }
        await LocationTracker.instance.start();
      } else {
        if (kDebugMode) {
          print('🚀 CUBIT: Tracker already running, updating config');
        }
        LocationTracker.instance.updateInterval(locationUpdateInterval);
      }

      final box = Hive.box<dynamic>(clockInOutDataBox);
      await box.put(clockInStatusKey, true);

      isClockIn = true;

      emit(ClockInOutSuccess(isClockedIn: isClockIn));
    } catch (e) {
      emit(ClockInOutError(message: e.toString()));
    }
  }
}

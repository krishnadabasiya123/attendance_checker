import 'dart:async';
import 'dart:isolate'; // Required for Isolate filtering
import 'dart:developer' as developer;
import 'package:attendance_system/Model/location_point.dart';
import 'package:attendance_system/utiils/connectivity.dart';
import 'package:attendance_system/utiils/hive_constant.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

class LocationRepository {
  static final String locationboxName = locationDataBox;
  // Mock API success flag for testing
  static bool mockLocationSyncSuccess = true;

  Box get _box => Hive.box(locationboxName);

  Future<void> saveLocal(LocationPoint point) async {
    final stopwatch = Stopwatch()..start();
    if (!Hive.isBoxOpen(locationboxName)) {
      await Hive.openBox(locationboxName);
    }
    final box = _box;
    final Map<dynamic, dynamic> todayData = Map<dynamic, dynamic>.from(
      box.get(point.date) ?? {},
    );

    final List<dynamic> locationList = List<dynamic>.from(
      todayData['location'] ?? [],
    );

    final newLocEntry = {
      "date": point.date,
      "time": point.timestamp.millisecondsSinceEpoch,
      "lat": point.latitude,
      "long": point.longitude,
    };

    locationList.add(newLocEntry);
    todayData['location'] = locationList;

    await box.put(point.date, todayData);
    stopwatch.stop();
    print(
      "⏱️ [LocationRepository] Storing location to Hive took: ${stopwatch.elapsedMilliseconds} ms (${stopwatch.elapsedMicroseconds} μs)",
    );
  }

  int getCount() {
    if (!Hive.isBoxOpen(locationboxName)) return 0;
    final todayStr = DateFormat("dd-MM-yyyy").format(DateTime.now());
    final box = _box;
    final todayData = box.get(todayStr);
    if (todayData is Map && todayData['location'] is List) {
      return (todayData['location'] as List).length;
    }
    return 0;
  }

  Future<Map<String, dynamic>> syncLocationsToServer({
    required String date,
    int? upToTimestamp,
    int? fromTimestamp,
    int chunkSize = 500,
  }) async {
    final locBox = await Hive.openBox(locationboxName);
    final locBoxData = locBox.get(date);

    bool isSyncSuccess = true;
    final List<dynamic> failedCoordinates = [];
    final List<dynamic> coordinatesToKeep = [];

    developer.log(
      "☁️ [LocationRepository] syncLocationsToServer called for date: $date",
    );
    if (locBoxData == null) {
      developer.log(
        "☁️ [LocationRepository] No location data found in Hive for date: $date",
      );
    }

    if (locBoxData != null &&
        locBoxData is Map &&
        locBoxData['location'] != null) {
      final List<dynamic> allLocations = List<dynamic>.from(
        locBoxData['location'],
      );

      developer.log(
        "☁️ [LocationRepository] Total coordinates in Hive for $date: ${allLocations.length}",
      );

      // ==========================================================
      // STEP 2: RUN THREAD-SAFE BACKGROUND FILTERING (ISOLATE)
      // ==========================================================
      // Moves filtering of potentially thousands of coordinates to a background thread to prevent UI lag.
      Map<String, List<dynamic>> filterResult;
      try {
        filterResult = await Isolate.run(() {
          return _filterLocations(allLocations, upToTimestamp, fromTimestamp);
        });
      } catch (e) {
        developer.log(
          "⚠️ [LocationRepository] Isolate.run failed or unsupported ($e). Falling back to main-thread filtering.",
        );
        filterResult = _filterLocations(
          allLocations,
          upToTimestamp,
          fromTimestamp,
        );
      }

      final List<dynamic> coordinatesToSync = filterResult['toSync']!;
      coordinatesToKeep.addAll(filterResult['toKeep']!);

      developer.log(
        "☁️ [LocationRepository] Filter result - coordinates to sync: ${coordinatesToSync.length}, coordinates to keep: ${coordinatesToKeep.length}",
      );

      // ==========================================================
      // STEP 3: CHUNKED UPLOAD LOOP (500 COORDINATES PER BATCH)
      // ==========================================================
      if (coordinatesToSync.isNotEmpty) {
        developer.log(
          "☁️ [LocationRepository] Uploading ${coordinatesToSync.length} coordinates in chunks of $chunkSize...",
        );
        for (int i = 0; i < coordinatesToSync.length; i += chunkSize) {
          int end = (i + chunkSize < coordinatesToSync.length)
              ? i + chunkSize
              : coordinatesToSync.length;

          final chunk = coordinatesToSync.sublist(i, end);

          // Verify active internet connection before sending this chunk
          final hasInternet = await InternetConnectivity.checkInternet();
          if (!isSyncSuccess || !hasInternet) {
            isSyncSuccess = false;
            failedCoordinates.addAll(
              coordinatesToSync.sublist(i),
            ); // Mark all remaining points as failed

            developer.log(
              "❌ [LocationRepository] Internet lost during sync! Failed remaining ${coordinatesToSync.length - i} coordinates.",
            );
            break;
          }

          final success = await _uploadLocationChunkApi(
            chunk,
            remainingCount: coordinatesToSync.length - i,
          );

          if (!success) {
            isSyncSuccess = false;
            failedCoordinates.addAll(coordinatesToSync.sublist(i));
            developer.log(
              "❌ [LocationRepository] Chunk upload failed. Aborting remaining chunks.",
            );
            break;
          }
        }

        // ==========================================================
        // STEP 4: UPDATE HIVE STORAGE WITH RESULTS (DELETE OR SAVE FAILURES)
        // ==========================================================
        final updatedLocs = [...failedCoordinates, ...coordinatesToKeep];
        if (updatedLocs.isEmpty) {
          // If everything synced successfully, clean up by deleting this date's records
          await locBox.delete(date);
          developer.log(
            "🎉 [LocationRepository] Success! All coordinates synced and removed from Hive for date: $date",
          );
        } else {
          // If any chunks failed or were filtered to be kept, write them back to Hive
          await locBox.put(date, {'location': updatedLocs});
          developer.log(
            "💾 [LocationRepository] Saved ${updatedLocs.length} coordinates back to Hive for date: $date",
          );
        }
      } else {
        developer.log(
          "☁️ [LocationRepository] No coordinates matched the sync window between $fromTimestamp and $upToTimestamp.",
        );
      }
    }
    return {'success': isSyncSuccess, 'failed': failedCoordinates};
  }

  /// Background helper for filtering locations running inside Isolate
  /// // get location in is sync (clock out time before all data from the location)
  static Map<String, List<dynamic>> _filterLocations(
    List<dynamic> locations,
    int? upToTimestamp,
    int? fromTimestamp,
  ) {
    final List<dynamic> sync = [];
    final List<dynamic> keep = [];

    for (final loc in locations) {
      if (loc is! Map) continue;

      final int? locTime = loc['time'] as int?;

      if (locTime == null) {
        sync.add(loc);
        continue;
      }

      final bool isAfterClockIn = fromTimestamp == null || locTime >= fromTimestamp;
      final bool isBeforeClockOut = upToTimestamp == null || locTime <= upToTimestamp;

      if (isAfterClockIn && isBeforeClockOut) {
        sync.add(loc);
      } else {
        keep.add(loc);
      }
    }
    return {'toSync': sync, 'toKeep': keep};
  }

  Future<bool> _uploadLocationChunkApi(
    List<dynamic> chunk, {
    int? remainingCount,
  }) async {
    try {
      developer.log(
        "APICALL _uploadLocationChunkApi Sending Location Chunk to Server (${chunk.length} items): $chunk",
      );
      // Simulate network request time
      // await Future.delayed(const Duration(milliseconds: 500));
      if (mockLocationSyncSuccess) {
        developer.log(
          "APICALL Location Batch Sync SUCCESS! Sent Payload size: ${chunk.length}",
        );
      } else {
        developer.log(
          "APICALL Location Batch Sync FAILED! Failed Chunk Payload: $chunk",
        );
      }
      return mockLocationSyncSuccess;
    } catch (e) {
      developer.log("APICALL Error uploading location chunk: $e");
      return false;
    }
  }
}

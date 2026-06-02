import 'dart:async';
import 'dart:developer' as developer;
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'package:attendance_system/repository/clock_in_out_repository.dart';
import 'package:attendance_system/repository/location_repository.dart';
import 'package:attendance_system/utiils/hive_constant.dart';
import 'package:attendance_system/utiils/connectivity.dart';
import 'package:attendance_system/service/manual_sync_service.dart';

/// Helper class to track a specific entry's value and its original position in Hive.
class EntryRef {
  final String dateKey;
  final int index;
  final Map<String, dynamic> entry;

  EntryRef({required this.dateKey, required this.index, required this.entry});
}

class BackgroundSyncService {
  BackgroundSyncService._();
  static final BackgroundSyncService instance = BackgroundSyncService._();

  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;
  Future<void>? _activeSync;
  Future<void>? get activeSyncFuture => _activeSync;
  StreamSubscription? _connectivitySubscription;
  bool _initialized = false;

  /// Starts background sync checking and network change listeners.
  void initialize() {
    if (_initialized) return;
    _initialized = true;

    // Check internet and trigger sync immediately on launch
    _triggerSync();

    // Listen for internet changes and trigger sync when connection is restored
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (_) => _triggerSync(),
    );

    developer.log(
      "🚀 [BackgroundSyncService] Initialized and listening for connection.",
    );
  }

  /// Cancels stream subscriptions when service is stopped.
  void dispose() {
    _connectivitySubscription?.cancel();
    _initialized = false;
  }

  /// Performs the actual synchronization run.
  Future<void> _runSyncDirectly() async {
    final hasInternet = await InternetConnectivity.checkInternet();
    if (!hasInternet) return;

    // Prevent conflict: If manual sync is currently active, abort background sync
    if (ManualSyncService.instance.isManualSyncing) {
      developer.log(
        "⚠️ [BackgroundSyncService] Manual sync is active. Aborting background sync to avoid conflict.",
      );
      return;
    }

    _isSyncing = true;
    _activeSync = syncAllPendingData();
    try {
      await _activeSync;
    } catch (e) {
      developer.log("[BackgroundSyncService] Error during sync: $e");
    } finally {
      _isSyncing = false;
      _activeSync = null;
    }
  }

  /// Triggers a sync run sequentially using the queue.
  Future<void> _triggerSync() async {
    await _runSyncDirectly();
  }

  /// Allows manual invocation of the sync process (e.g. from the Clock-Out button click).
  Future<void> forceManualSync() async {
    developer.log("🔄 [BackgroundSyncService] Manual sync requested.");

    await _runSyncDirectly();
  }

  /// Core sync logic: collects entries, sorts chronologically, pairs them, and flushes locations.
  Future<void> syncAllPendingData() async {
    final box = Hive.box(clockInOutDataBox);

    // STEP 1: Find all Hive keys matching date format (dd-MM-yyyy)
    final dateKeys = box.keys.where((key) {
      if (key is! String) return false;
      final parts = key.split('-');
      return parts.length == 3 && parts.every((p) => int.tryParse(p) != null);
    }).toList();

    if (dateKeys.isEmpty) return;

    // STEP 2: Collect all entries from those dates with their original indices
    // new date come new index start from 0
    final List<EntryRef> allRefs = [];
    for (final dateKey in dateKeys) {
      final list = box.get(dateKey);
      if (list is List) {
        for (int i = 0; i < list.length; i++) {
          final item = list[i];
          if (item is Map) {
            allRefs.add(
              EntryRef(
                dateKey: dateKey as String,
                index: i,
                entry: Map<String, dynamic>.from(item),
              ),
            );
          }
        }
      }
    }

    // STEP 3: Sort all entries chronologically by their timestamp
    allRefs.sort((a, b) {
      final timeA = a.entry['time'] as int? ?? 0;
      final timeB = b.entry['time'] as int? ?? 0;
      return timeA.compareTo(timeB);
    });

    // STEP 4: Pair matching 'in' and 'out' entries chronologically and sync them
    int i = 0;
    while (i < allRefs.length) {
      final currentRef = allRefs[i];
      final currentType = currentRef.entry['type'] as String?;

      if (currentType == 'in') {
        if (i + 1 < allRefs.length) {
          final nextRef = allRefs[i + 1];
          final nextType = nextRef.entry['type'] as String?;

          // If a complete 'in' and 'out' pair is found, process the synchronization
          if (nextType == 'out') {
            final bool pairProcessed = await _syncPair(currentRef, nextRef);
            if (!pairProcessed) break; // Halt if any pair fails
            i += 2;
            continue;
          }
        }
        // Last entry is 'in' (active shift, has no matching 'out' yet).
        // "last entry if in then not send to server" - skip syncing this entry.
        break;
      } else {
        // Skip out-of-order 'out' entries
        i++;
      }
    }

    // STEP 5: Cleanup Pass: Delete completed historical dates from Hive.
    await cleanCompletedDates();
  }

  // remove old data (only if all isSync is true , last entry is out)
  Future<void> cleanCompletedDates() async {
    final box = Hive.box(clockInOutDataBox);
    final formatter = DateFormat('dd-MM-yyyy');

    // Get all valid date keys
    final List<String> dateKeys = box.keys.whereType<String>().where((key) {
      final parts = key.split('-');
      return parts.length == 3 && parts.every((e) => int.tryParse(e) != null);
    }).toList();

    if (dateKeys.isEmpty) return;

    // Sort dates ascending
    dateKeys.sort((a, b) => formatter.parse(a).compareTo(formatter.parse(b)));

    final List<String> datesToDelete = [];

    for (int i = 0; i < dateKeys.length; i++) {
      final currentKey = dateKeys[i];

      final currentList = box.get(currentKey);

      if (currentList is! List || currentList.isEmpty) {
        continue;
      }

      final entries = currentList
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      // Check:
      // 1. All entries synced
      // 2. Last entry is clock-out
      final bool canClean =
          entries.every((e) => e['isSync'] == true) &&
          entries.last['type'] == 'out';

      if (!canClean) continue;

      bool hasNextClockIn = false;

      // Check future dates for clock-in
      for (int j = i + 1; j < dateKeys.length; j++) {
        final nextList = box.get(dateKeys[j]);

        if (nextList is List &&
            nextList.any((e) => e is Map && e['type'] == 'in')) {
          // new date clock in check (when new clock in old date data remove from the hive)
          hasNextClockIn = true;
          break;
        }
      }

      if (hasNextClockIn) {
        datesToDelete.add(currentKey);
      }
    }

    // Delete old completed dates
    for (final key in datesToDelete) {
      await box.delete(key);

      developer.log(
        "🧹 [BackgroundSyncService] Cleaned up historical date: $key",
      );
    }
  }

  /// Syncs an individual matched 'in' and 'out' pair.
  Future<bool> _syncPair(EntryRef inRef, EntryRef outRef) async {
    final repository = ClockInOutRepository();
    final box = Hive.box(clockInOutDataBox);

    // 1. Sync the 'in' entry
    bool inSync = inRef.entry['isSync'] as bool? ?? false;
    if (!inSync) {
      inSync = await repository.clockInApiDirectly(inRef.entry);
      inRef.entry['isSync'] = inSync;

      // Update entry in Hive
      final list = List<dynamic>.from(box.get(inRef.dateKey) ?? []);
      if (inRef.index < list.length) {
        list[inRef.index] = inRef.entry;
        await box.put(inRef.dateKey, list);
      }

      // If the 'in' API fails, stop syncing further pairs
      if (!inSync) return false;
    }

    // 2. Sync location coordinates recorded in the shift interval (handles rollover dates)
    // This runs after clock-in succeeded but before clock-out is sent to the server.
    final bool locSyncSuccess = await _syncLocationsForPair(
      inRef.entry,
      outRef.entry,
    );
    if (!locSyncSuccess) {
      developer.log(
        "⚠️ [BackgroundSyncService] Location sync failed for pair. Halting out sync.",
      );
      return false;
    }

    // 3. Sync the corresponding 'out' entry
    bool outSync = outRef.entry['isSync'] as bool? ?? false;
    if (!outSync) {
      outSync = await repository.clockOutApiDirectly(outRef.entry);
      outRef.entry['isSync'] = outSync;

      // Update entry in Hive to store synced state of clock-out
      final list = List<dynamic>.from(box.get(outRef.dateKey) ?? []);
      if (outRef.index < list.length) {
        list[outRef.index] = outRef.entry;
        await box.put(outRef.dateKey, list);
      }

      if (!outSync) return false;
    }

    return true;
  }

  /// Identifies and syncs coordinates recorded on all days spanned by the shift (handles rollovers).
  Future<bool> _syncLocationsForPair(
    Map<String, dynamic> inEntry,
    Map<String, dynamic> outEntry,
  ) async {
    final int? fromTimestamp = inEntry['time'] as int?;
    final int? upToTimestamp = outEntry['time'] as int?;

    if (fromTimestamp == null || upToTimestamp == null) return true;

    final DateTime startDate = DateTime.fromMillisecondsSinceEpoch(
      fromTimestamp,
    );
    final DateTime endDate = DateTime.fromMillisecondsSinceEpoch(upToTimestamp);

    // Collect all date strings spanned by this shift (e.g. May 27th & May 28th)
    final List<String> datesToSync = [];
    DateTime current = DateTime(startDate.year, startDate.month, startDate.day);
    final DateTime endDay = DateTime(endDate.year, endDate.month, endDate.day);

    while (!current.isAfter(endDay)) {
      datesToSync.add(DateFormat('dd-MM-yyyy').format(current));
      current = current.add(const Duration(days: 1));
    }

    // Trigger location sync in 500-sized chunked uploads for each spanned date
    bool allSuccess = true;
    for (final syncDate in datesToSync) {
      final syncResult = await LocationRepository().syncLocationsToServer(
        date: syncDate,
        upToTimestamp: upToTimestamp,
        fromTimestamp: fromTimestamp,
        chunkSize: 500,
      );
      if (!(syncResult['success'] ?? false)) {
        allSuccess = false;
      }
    }
    return allSuccess;
  }
}

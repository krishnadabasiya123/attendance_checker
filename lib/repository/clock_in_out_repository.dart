import 'dart:developer' as developer;
import 'package:hive/hive.dart';
import 'package:attendance_system/utiils/hive_constant.dart';
import 'package:attendance_system/utiils/connectivity.dart';

class ClockInOutRepository {
  // Mock API success flag for testing clock in/out
  static bool mockClockInOutSuccess = true;

  Future<void> setClockInOut({
    required String date,
    required Map<String, dynamic> entry,
  }) async {
    try {
      final box = Hive.box(clockInOutDataBox);

      final updatedEntry = Map<String, dynamic>.from(entry);
      final type = updatedEntry['type'] as String?;

      bool isSync = false;

      if (await InternetConnectivity.checkInternet()) {
        switch (type) {
          case 'in':
            isSync = await _clockInApi(updatedEntry);
            break;

          case 'out':
            isSync = await _clockOutApi(updatedEntry);
            break;
        }
      }

      updatedEntry['isSync'] = isSync;

      // Append new entry efficiently
      final existingEntries = (box.get(date) as List<dynamic>? ?? <dynamic>[])
        ..add(updatedEntry);

      await box.put(date, existingEntries);
    } catch (e) {
      throw Exception('Error in setClockInOut: $e');
    }
  }

  Future<bool> _clockInApi(Map<String, dynamic> entry) async {
    try {
      developer.log("APICALL _clockInApi Sending Clock In to Server: $entry");
      // await Future.delayed(const Duration(milliseconds: 300));
      return mockClockInOutSuccess;
    } catch (e) {
      developer.log("APICALL Clock In FAILED: $e");
      return false;
    }
  }

  Future<bool> _clockOutApi(Map<String, dynamic> entry) async {
    try {
      developer.log("APICALL _clockOutApi Sending Clock Out to Server: $entry");
      // await Future.delayed(const Duration(milliseconds: 300));
      return mockClockInOutSuccess;
    } catch (e) {
      developer.log("APICALL Clock Out FAILED: $e");
      return false;
    }
  }

  Future<bool> clockInApiDirectly(Map<String, dynamic> entry) async {
    return await _clockInApi(entry);
  }

  Future<bool> clockOutApiDirectly(Map<String, dynamic> entry) async {
    return await _clockOutApi(entry);
  }
}

import 'package:attendance_system/utiils/hive_constant.dart';
import 'package:hive_flutter/adapters.dart';

class SettingLocalRepository {
  SettingLocalRepository._();

  static const String _locationUpdateIntervalKey = 'locationUpdateInterval';

  static Box<dynamic> get _box => Hive.box<dynamic>(boxName);
  static final SettingLocalRepository instance = SettingLocalRepository._();

  /* -------------------- Location Update Interval -------------------- */
  Future<void> setLocationUpdateInterval(int interval) async {
    await _box.put(_locationUpdateIntervalKey, interval);
  }

  int getLocationUpdateInterval() {
    return _box.get(_locationUpdateIntervalKey, defaultValue: 1) as int;
  }
}

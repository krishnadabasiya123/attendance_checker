import 'package:attendance_system/utiils/hive_constant.dart';
import 'package:hive_flutter/hive_flutter.dart';

class HiveUtils {
  static Future<void> openBox() async {
    await Hive.openBox<dynamic>(authBox);
    await Hive.openBox<dynamic>(locationDataBox);
    await Hive.openBox<dynamic>(clockInOutDataBox);
    await Hive.openBox<dynamic>(boxName);
  }

  // Clear all Hive boxes synchronously since they are already opened
  static Future<void> clearHiveData() async {
    final dateBox = Hive.box<dynamic>(clockInOutDataBox);
    await dateBox.clear();

    final locBox = Hive.box<dynamic>(locationDataBox);
    await locBox.clear();

    final userBox = Hive.box<dynamic>(authBox);
    await userBox.clear();
  }
}

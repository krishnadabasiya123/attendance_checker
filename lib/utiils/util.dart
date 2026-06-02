import 'package:attendance_system/repository/system_local_repository.dart';
import 'package:intl/intl.dart';

int get timestamp => DateTime.now().millisecondsSinceEpoch;
String get todayStr => DateFormat("dd-MM-yyyy").format(DateTime.now());
int get locationUpdateInterval =>
    SettingLocalRepository.instance.getLocationUpdateInterval();

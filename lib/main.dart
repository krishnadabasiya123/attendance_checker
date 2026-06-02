import 'package:attendance_system/screen/clockInOutScreen.dart';
import 'package:attendance_system/utiils/hive_constant.dart';
import 'package:attendance_system/utiils/hive_utils.dart';
import 'package:attendance_system/cubit/cubit/clock_in_out_cubit.dart';
import 'package:attendance_system/cubit/cubit/user_details_cubit.dart';
import 'package:attendance_system/utiils/util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:attendance_system/service/location_service.dart';
import 'package:attendance_system/service/background_sync_service.dart';

Future<void> _requestLocationPermission() async {
  bool serviceEnabled;
  LocationPermission permission;

  serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    print('Location services are disabled.');
    return;
  }

  permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      print('Location permissions are denied.');
      return;
    }
  }

  if (permission == LocationPermission.deniedForever) {
    print('Location permissions are permanently denied.');
    return;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive
  await Hive.initFlutter();
  await HiveUtils.openBox();

  BackgroundSyncService.instance.initialize();

  await _requestLocationPermission();

  // Create UserDetailsCubit, trigger fetch to load user details from Hive
  final userCubit = UserDetailsCubit();
  userCubit.fetchUserDetails();

  // CHECK: Print loaded details for testing and verification
  final currentState = userCubit.state;
  if (currentState is UserDetailsLoaded) {
    debugPrint("=================================================");
    debugPrint(" HIVE TEST CHECK: User Details Loaded Successfully!");
    debugPrint(" Name: ${currentState.user.name}");
    debugPrint(" Email: ${currentState.user.email}");
    debugPrint(" Clock-In Status: ${currentState.user.isClockedIn}");
    debugPrint("=================================================");

    // Start location tracking on app launch if the user is already clocked in
    final clockBox = Hive.box<dynamic>(clockInOutDataBox);
    final isClockedIn =
        clockBox.get(clockInStatusKey, defaultValue: false) as bool;

    if (isClockedIn) {
      if (!LocationTracker.instance.isRunning) {
        debugPrint('🚀 MAIN: Starting location tracking for active shift');
        await LocationTracker.instance.start();
      } else {
        LocationTracker.instance.updateInterval(locationUpdateInterval);
      }
    } else {
      await LocationTracker.instance.stop();
    }
  } else {
    debugPrint(" HIVE TEST CHECK: Initialized UserDetailsCubit");
  }

  runApp(MyApp(userDetailsCubit: userCubit));
}

class MyApp extends StatelessWidget {
  final UserDetailsCubit? userDetailsCubit;

  const MyApp({super.key, this.userDetailsCubit});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<ClockInOutCubit>(create: (context) => ClockInOutCubit()),
        BlocProvider<UserDetailsCubit>(
          create: (context) {
            final cubit = userDetailsCubit ?? UserDetailsCubit();
            if (cubit.state is UserDetailsInitial) {
              cubit.fetchUserDetails();
            }
            return cubit;
          },
        ),
      ],
      child: const MaterialApp(
        title: 'Attendance System',
        debugShowCheckedModeBanner: false,
        home: ClockInOutScreen(),
      ),
    );
  }
}

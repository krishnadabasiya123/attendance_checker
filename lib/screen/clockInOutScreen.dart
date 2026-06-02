import 'package:attendance_system/service/location_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:attendance_system/cubit/cubit/clock_in_out_cubit.dart';
import 'package:attendance_system/cubit/cubit/user_details_cubit.dart';
import 'package:attendance_system/utiils/hive_utils.dart';
import 'package:attendance_system/utiils/hive_constant.dart';
import 'package:attendance_system/screen/widgets/database_inspector.dart';
import 'package:attendance_system/screen/widgets/attendance_dialogs.dart';
import 'package:attendance_system/screen/widgets/premium_header.dart';
import 'package:attendance_system/screen/widgets/pulsing_fingerprint_button.dart';
import 'package:attendance_system/screen/widgets/system_controls_console.dart';

class ClockInOutScreen extends StatefulWidget {
  const ClockInOutScreen({super.key});

  @override
  State<ClockInOutScreen> createState() => _ClockInOutScreenState();
}

class _ClockInOutScreenState extends State<ClockInOutScreen>
    with SingleTickerProviderStateMixin {
  // Simple state toggle to showcase both 'Clock In' and 'Clock Out' UI designs
  bool _isClockedIn = false;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    // Initialize the breathing animation controller (1.8-second seamless loop)
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ClockInOutCubit>().loadClockStatus();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose(); // Graceful disposal of resource ticker
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Premium Dark Theme Color System (State-of-the-Art Palette)
    const Color backgroundTop = Color(0xFF0F172A); // Deep Slate Blue
    const Color backgroundBottom = Color(0xFF020617); // Rich Near-Black Blue
    const Color redColor = Color(0xFFF43F5E); // Premium Coral Rose

    return Scaffold(
      body: BlocConsumer<ClockInOutCubit, ClockInOutState>(
        listener: (context, state) {
          if (state is ClockInOutSuccess) {
            setState(() {
              _isClockedIn = state.isClockedIn;
            });
            context.read<UserDetailsCubit>().updateClockStatus(
              state.isClockedIn,
            );
          } else if (state is ClockInOutError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: redColor,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            );
          }
        },
        builder: (context, state) {
          return Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [backgroundTop, backgroundBottom],
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  // ==========================================
                  // 1. PREMIUM HEADER SECTION
                  // ==========================================
                  const PremiumHeader(),

                  // ==========================================
                  // 2. SCROLLABLE MAIN BODY
                  // ==========================================
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 24.0),
                      child: Column(
                        children: [
                          const SizedBox(height: 15),

                          // PULSING FINGERPRINT BUTTON
                          PulsingFingerprintButton(
                            isClockedIn: _isClockedIn,
                            isLoading: state is ClockInOutLoading,
                            pulseAnimation: _pulseAnimation,
                            onTap: () {
                              context.read<ClockInOutCubit>().setClockInOut(
                                isClockIn: _isClockedIn,
                              );
                            },
                          ),

                          const SizedBox(height: 40),

                          // BOTTOM ACTION CONTROL PANEL
                          SystemControlsConsole(
                            onViewLogs: () => DatabaseInspector.show(context),
                            onClearData: () => _handleClearData(context),
                            onSeedDummyData: () async {
                              _seedDummyData();
                              await LocationTracker.instance.stop();
                            },
                          ),

                          const SizedBox(height: 25),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _handleClearData(BuildContext context) async {
    await AttendanceDialogs.showClearConfirmation(
      context,
      onConfirm: () async {
        await LocationTracker.instance.stop();
        await HiveUtils.clearHiveData();

        if (context.mounted) {
          context.read<ClockInOutCubit>().loadClockStatus();
          context.read<UserDetailsCubit>().fetchUserDetails();

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 12),
                  Text(
                    "Hive Database successfully cleared!",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF10B981),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
      },
    );
  }

  Future<void> _seedDummyData() async {
    try {
      final box = Hive.box<dynamic>(clockInOutDataBox);
      final locBox = Hive.box<dynamic>(locationDataBox);

      // Clear existing data first
      await box.clear();
      await locBox.clear();

      // Helper to generate locations evenly inside a time range
      List<Map<String, dynamic>> generateLocationsRange({
        required String dateStr,
        required int startTime,
        required int endTime,
        required int count,
      }) {
        final List<Map<String, dynamic>> locs = [];
        if (count <= 0) return locs;
        final int step = count > 1 ? (endTime - startTime) ~/ (count - 1) : 0;
        for (int i = 0; i < count; i++) {
          locs.add({
            "date": dateStr,
            "time": startTime + (i * step),
            "lat": 23.23825 + (i * 0.00001),
            "long": 69.68097 + (i * 0.00001),
          });
        }
        return locs;
      }

      // --- 1. SEED CLOCK IN/OUT SESSIONS ---

      // May 26th Timestamps
      final dt26In1 = DateTime(2026, 5, 26, 9, 0).millisecondsSinceEpoch;
      final dt26Out1 = DateTime(2026, 5, 26, 13, 0).millisecondsSinceEpoch;
      final dt26In2 = DateTime(2026, 5, 26, 14, 0).millisecondsSinceEpoch;
      final dt26Out2 = DateTime(2026, 5, 26, 15, 0).millisecondsSinceEpoch;

      await box.put("26-05-2026", [
        {
          "type": "in",
          "time": dt26In1,
          "lat": "23.23825",
          "long": "69.68097",
          "isSync": false,
        },
        {
          "type": "out",
          "time": dt26Out1,
          "lat": "23.23983",
          "long": "69.68378",
          "isSync": false,
        },
        {
          "type": "in",
          "time": dt26In2,
          "lat": "23.23825",
          "long": "69.68097",
          "isSync": false,
        },
        {
          "type": "out",
          "time": dt26Out2,
          "lat": "23.23983",
          "long": "69.68378",
          "isSync": false,
        },
      ]);

      // May 27th Timestamps
      final dt27In1 = DateTime(2026, 5, 27, 9, 0).millisecondsSinceEpoch;
      final dt27Out1 = DateTime(2026, 5, 27, 13, 0).millisecondsSinceEpoch;
      final dt27In2 = DateTime(2026, 5, 27, 14, 0).millisecondsSinceEpoch;
      final dt27Out2 = DateTime(2026, 5, 27, 15, 0).millisecondsSinceEpoch;

      await box.put("27-05-2026", [
        {
          "type": "in",
          "time": dt27In1,
          "lat": "23.23825",
          "long": "69.68097",
          "isSync": false,
        },
        {
          "type": "out",
          "time": dt27Out1,
          "lat": "23.23983",
          "long": "69.68378",
          "isSync": false,
        },
        {
          "type": "in",
          "time": dt27In2,
          "lat": "23.23825",
          "long": "69.68097",
          "isSync": false,
        },
        {
          "type": "out",
          "time": dt27Out2,
          "lat": "23.23983",
          "long": "69.68378",
          "isSync": false,
        },
      ]);

      // May 28th Timestamps
      final dt28In1 = DateTime(2026, 5, 28, 9, 0).millisecondsSinceEpoch;
      final dt28Out1 = DateTime(2026, 5, 28, 13, 0).millisecondsSinceEpoch;
      final dt28In2 = DateTime(2026, 5, 28, 14, 0).millisecondsSinceEpoch;
      final dt28Out2 = DateTime(2026, 5, 28, 15, 0).millisecondsSinceEpoch;

      await box.put("28-05-2026", [
        {
          "type": "in",
          "time": dt28In1,
          "lat": "23.23825",
          "long": "69.68097",
          "isSync": false,
        },
        {
          "type": "out",
          "time": dt28Out1,
          "lat": "23.23983",
          "long": "69.68378",
          "isSync": false,
        },
        {
          "type": "in",
          "time": dt28In2,
          "lat": "23.23825",
          "long": "69.68097",
          "isSync": false,
        },
        {
          "type": "out",
          "time": dt28Out2,
          "lat": "23.23983",
          "long": "69.68378",
          "isSync": false,
        },
      ]);

      // May 29th Timestamps
      final dt29In1 = DateTime(2026, 5, 29, 9, 0).millisecondsSinceEpoch;
      final dt29Out1 = DateTime(2026, 5, 29, 13, 0).millisecondsSinceEpoch;
      final dt29In2 = DateTime(2026, 5, 29, 14, 0).millisecondsSinceEpoch;
      final dt30Out2 = DateTime(2026, 5, 30, 10, 0).millisecondsSinceEpoch;

      await box.put("29-05-2026", [
        {
          "type": "in",
          "time": dt29In1,
          "lat": "23.23825",
          "long": "69.68097",
          "isSync": false,
        },
        {
          "type": "out",
          "time": dt29Out1,
          "lat": "23.23983",
          "long": "69.68378",
          "isSync": false,
        },
        {
          "type": "in",
          "time": dt29In2,
          "lat": "23.23825",
          "long": "69.68097",
          "isSync": false,
        },
        {
          "type": "out",
          "time": dt30Out2,
          "lat": "23.23983",
          "long": "69.68378",
          "isSync": false,
        },
      ]);

      // May 30th Timestamps
      final dt30In3 = DateTime(2026, 5, 30, 10, 30).millisecondsSinceEpoch;
      final dt30Out3 = DateTime(2026, 5, 30, 13, 0).millisecondsSinceEpoch;
      final dt30In4 = DateTime(2026, 5, 30, 14, 0).millisecondsSinceEpoch;
      final dt31Out4 = DateTime(2026, 5, 31, 9, 0).millisecondsSinceEpoch;

      await box.put("30-05-2026", [
        {
          "type": "in",
          "time": dt30In3,
          "lat": "23.23825",
          "long": "69.68097",
          "isSync": false,
        },
        {
          "type": "out",
          "time": dt30Out3,
          "lat": "23.23983",
          "long": "69.68378",
          "isSync": false,
        },
        {
          "type": "in",
          "time": dt30In4,
          "lat": "23.23825",
          "long": "69.68097",
          "isSync": false,
        },
        {
          "type": "out",
          "time": dt31Out4,
          "lat": "23.23983",
          "long": "69.68378",
          "isSync": false,
        },
      ]);

      // --- 2. SEED LOCATION DATA ---

      // 2a. May 26th Locations: 2000 points (Shift 1) + 3000 points (Shift 2)
      final List<Map<String, dynamic>> locations26 = [
        ...generateLocationsRange(
          dateStr: "26-05-2026",
          startTime: dt26In1,
          endTime: dt26Out1,
          count: 1000,
        ),
        ...generateLocationsRange(
          dateStr: "26-05-2026",
          startTime: dt26In2,
          endTime: dt26Out2,
          count: 1000,
        ),
      ];
      await locBox.put("26-05-2026", {"location": locations26});

      // 2b. May 27th Locations: 2000 points (Shift 1) + 3000 points (Shift 2)
      final List<Map<String, dynamic>> locations27 = [
        ...generateLocationsRange(
          dateStr: "27-05-2026",
          startTime: dt27In1,
          endTime: dt27Out1,
          count: 1000,
        ),
        ...generateLocationsRange(
          dateStr: "27-05-2026",
          startTime: dt27In2,
          endTime: dt27Out2,
          count: 1000,
        ),
      ];
      await locBox.put("27-05-2026", {"location": locations27});

      // 2c. May 28th Locations: 2000 points (Shift 1) + 3000 points (Shift 2)
      final List<Map<String, dynamic>> locations28 = [
        ...generateLocationsRange(
          dateStr: "28-05-2026",
          startTime: dt28In1,
          endTime: dt28Out1,
          count: 1000,
        ),
        ...generateLocationsRange(
          dateStr: "28-05-2026",
          startTime: dt28In2,
          endTime: dt28Out2,
          count: 1000,
        ),
      ];
      await locBox.put("28-05-2026", {"location": locations28});

      // 2d. May 29th Locations: 4000 points (Shift 1) + 2000 points (Shift 2 start on 29th)
      final end29OfDay = DateTime(
        2026,
        5,
        29,
        23,
        59,
        59,
      ).millisecondsSinceEpoch;
      final List<Map<String, dynamic>> locations29 = [
        ...generateLocationsRange(
          dateStr: "29-05-2026",
          startTime: dt29In1,
          endTime: dt29Out1,
          count: 1000,
        ),
        ...generateLocationsRange(
          dateStr: "29-05-2026",
          startTime: dt29In2,
          endTime: end29OfDay,
          count: 1000,
        ),
      ];
      await locBox.put("29-05-2026", {"location": locations29});

      // 2e. May 30th Locations:
      // - 2000 points (Shift 2 rollover from 12:00 AM to 10:00 AM)
      // - 3000 points (Shift 3 from 10:30 AM to 01:00 PM)
      // - 1000 points (Shift 4 start from 02:00 PM to midnight)
      final start30OfDay = DateTime(2026, 5, 30, 0, 0).millisecondsSinceEpoch;
      final end30OfDay = DateTime(
        2026,
        5,
        30,
        23,
        59,
        59,
      ).millisecondsSinceEpoch;
      final List<Map<String, dynamic>> locations30 = [
        ...generateLocationsRange(
          dateStr: "30-05-2026",
          startTime: start30OfDay,
          endTime: dt30Out2,
          count: 1000,
        ),
        ...generateLocationsRange(
          dateStr: "30-05-2026",
          startTime: dt30In3,
          endTime: dt30Out3,
          count: 1000,
        ),
        ...generateLocationsRange(
          dateStr: "30-05-2026",
          startTime: dt30In4,
          endTime: end30OfDay,
          count: 1000,
        ),
      ];
      await locBox.put("30-05-2026", {"location": locations30});

      // 2f. May 31st Locations: 1000 points (Shift 4 rollover from 12:00 AM to 09:00 AM)
      final start31OfDay = DateTime(2026, 5, 31, 0, 0).millisecondsSinceEpoch;
      final List<Map<String, dynamic>> locations31 = [
        ...generateLocationsRange(
          dateStr: "31-05-2026",
          startTime: start31OfDay,
          endTime: dt31Out4,
          count: 1000,
        ),
      ];
      await locBox.put("31-05-2026", {"location": locations31});

      // Since all seeded shifts are completed, user is currently OFF duty
      await box.put(clockInStatusKey, false);

      // Force UI reload
      if (mounted) {
        context.read<ClockInOutCubit>().loadClockStatus();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text(
                  "Dummy data successfully seeded!",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint("Error seeding Hive data: $e");
    }
  }
}

import 'dart:convert';
import 'package:attendance_system/utiils/hive_constant.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

class DatabaseInspector {
  static void show(BuildContext context) {
    try {
      final dateBox = Hive.box<dynamic>(clockInOutDataBox);
      final locBox = Hive.box<dynamic>(locationDataBox);

      // Helper to recursively convert Map keys to String so JsonEncoder can serialize it safely.
      Map<String, dynamic> stringifyKeys(Map<dynamic, dynamic> map) {
        return map.map((key, value) {
          final stringKey = key.toString();
          var formattedValue = value;

          if ((stringKey == 'time' || stringKey == 'timestamp') && value != null) {
            try {
              DateTime? dt;
              if (value is int) {
                dt = DateTime.fromMillisecondsSinceEpoch(value);
              } else if (value is String) {
                final parsedInt = int.tryParse(value);
                if (parsedInt != null) {
                  dt = DateTime.fromMillisecondsSinceEpoch(parsedInt);
                } else {
                  dt = DateTime.tryParse(value);
                }
              }
              if (dt != null) {
                formattedValue = DateFormat("d MMMM yyyy 'at' H:mm:ss.SSS").format(dt);
              }
            } catch (_) {}
          }

          if (formattedValue is Map) {
            return MapEntry(stringKey, stringifyKeys(formattedValue));
          } else if (formattedValue is List) {
            return MapEntry(
              stringKey,
              formattedValue.map((item) {
                if (item is Map) {
                  return stringifyKeys(item);
                }
                return item;
              }).toList(),
            );
          }
          return MapEntry(stringKey, formattedValue);
        });
      }

      final clokINOutData = stringifyKeys(dateBox.toMap());
      final locData = stringifyKeys(locBox.toMap());

      final encoder = const JsonEncoder.withIndent('  ');

      showModalBottomSheet(
        context: context,
        backgroundColor: const Color(0xFF0F172A),
        isScrollControlled: true, // Allow it to expand nicely
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (context) {
          String selectedBox = clockInOutDataBox; // Default selected tab

          return StatefulBuilder(
            builder: (context, setSheetState) {
              final Map<dynamic, dynamic> currentData =
                  selectedBox == clockInOutDataBox ? clokINOutData : locData;
              final String boxJsonStr = encoder.convert(currentData);

              return FractionallySizedBox(
                heightFactor: 0.75, // Lock it to a beautiful, clean height
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20.0,
                    vertical: 20.0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- Drag Handle ---
                      Center(
                        child: Container(
                          width: 42,
                          height: 4.5,
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2.5),
                          ),
                        ),
                      ),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            "Database Inspector",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // --- Interactive Tab Selectors ---
                      Row(
                        children: [
                          _buildTabButton(
                            label: "Sessions (clockInOutData)",
                            isSelected: selectedBox == clockInOutDataBox,
                            onTap: () {
                              setSheetState(() {
                                selectedBox = clockInOutDataBox;
                              });
                            },
                          ),
                          const SizedBox(width: 10),
                          _buildTabButton(
                            label: "Locations (locationData)",
                            isSelected: selectedBox == locationDataBox,
                            onTap: () {
                              setSheetState(() {
                                selectedBox = locationDataBox;
                              });
                            },
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // --- Coordinate and Session Summary Card ---
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0x0CFFFFFF),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  selectedBox == locationDataBox
                                      ? Icons.location_on
                                      : Icons.fingerprint,
                                  color: selectedBox == locationDataBox
                                      ? const Color(0xFF6366F1)
                                      : const Color(0xFF10B981),
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  selectedBox == locationDataBox
                                      ? "Location Coordinates Count"
                                      : "Shift Session Actions Count",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (currentData.isEmpty)
                              const Text(
                                "No records found.",
                                style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic,
                                ),
                              )
                            else
                              ...currentData.entries
                                  .where(
                                    (entry) =>
                                        entry.key != clockInStatusKey &&
                                        entry.key != 'is_clocked_in',
                                  )
                                  .map((entry) {
                                    final dateStr = entry.key;
                                    final dynamic value = entry.value;
                                    int count = 0;

                                    if (selectedBox == locationDataBox) {
                                      if (value is Map &&
                                          value['location'] is List) {
                                        count =
                                            (value['location'] as List).length;
                                      }
                                    } else {
                                      if (value is List) {
                                        count = value.length;
                                      }
                                    }

                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 3.0,
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            dateStr.toString(),
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 12,
                                              fontFamily: 'monospace',
                                            ),
                                          ),
                                          Text(
                                            selectedBox == locationDataBox
                                                ? "$count points"
                                                : "$count events",
                                            style: TextStyle(
                                              color:
                                                  selectedBox == locationDataBox
                                                  ? (count >= 5000
                                                        ? const Color(
                                                            0xFFEF4444,
                                                          )
                                                        : const Color(
                                                            0xFF38BDF8,
                                                          ))
                                                  : const Color(0xFF10B981),
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              fontFamily: 'monospace',
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                          ],
                        ),
                      ),

                      // --- Display Container ---
                      Expanded(
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: SingleChildScrollView(
                            child: SelectableText(
                              currentData.isEmpty
                                  ? "{} (No records found)"
                                  : boxJsonStr,
                              style: const TextStyle(
                                color: Color(0xFF38BDF8),
                                fontFamily: 'monospace',
                                fontSize: 13.0,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    } catch (e) {
      debugPrint("Error reading Hive: $e");
    }
  }

  static Widget _buildTabButton({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? Colors.blue.shade600 : const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? Colors.blue.shade400 : Colors.white10,
              width: 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.white70,
              fontWeight: FontWeight.bold,
              fontSize: 12.0,
            ),
          ),
        ),
      ),
    );
  }
}

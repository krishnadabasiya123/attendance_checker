import 'package:equatable/equatable.dart';
import 'package:hive_flutter/hive_flutter.dart';

// ---------------------------------------------------------------------------
// LOCATION POINT DATA MODEL
// ---------------------------------------------------------------------------
class LocationPoint extends Equatable {
  const LocationPoint({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.speed = 0,
    required this.date,
  });

  factory LocationPoint.fromJson(Map<String, dynamic> json) {
    final rawTime = json['time'] ?? json['timestamp'];
    DateTime parsedTime;
    if (rawTime is int) {
      parsedTime = DateTime.fromMillisecondsSinceEpoch(rawTime);
    } else if (rawTime is String) {
      final parsedInt = int.tryParse(rawTime);
      if (parsedInt != null) {
        parsedTime = DateTime.fromMillisecondsSinceEpoch(parsedInt);
      } else {
        parsedTime = DateTime.parse(rawTime);
      }
    } else {
      parsedTime = DateTime.now();
    }

    return LocationPoint(
      latitude: (json['lat'] as num).toDouble(),
      longitude: (json['lon'] as num).toDouble(),
      speed: (json['speed'] as num?)?.toDouble() ?? 0.0,
      timestamp: parsedTime,
      date: json['date'] as String,
    );
  }
  final double latitude;
  final double longitude;
  final double speed;
  final DateTime timestamp;
  final String date;

  Map<String, dynamic> toJson() => {
    'lat': latitude,
    'lon': longitude,
    'time': timestamp.toIso8601String(),
    'speed': speed,
    'date': date,
  };

  @override
  List<Object?> get props => [latitude, longitude, timestamp, speed, date];
}

// ---------------------------------------------------------------------------
// HIVE ADAPTER FOR LOCAL STORAGE
// ---------------------------------------------------------------------------
class LocationPointAdapter extends TypeAdapter<LocationPoint> {
  @override
  final int typeId = 1; // Using typeId 1 (0 might be used elsewhere)

  @override
  LocationPoint read(BinaryReader reader) {
    return LocationPoint(
      latitude: reader.readDouble(),
      longitude: reader.readDouble(),
      speed: reader.readDouble(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(reader.readInt()),
      date: reader.readString(),
    );
  }

  @override
  void write(BinaryWriter writer, LocationPoint obj) {
    writer
      ..writeDouble(obj.latitude)
      ..writeDouble(obj.longitude)
      ..writeDouble(obj.speed)
      ..writeInt(obj.timestamp.millisecondsSinceEpoch)
      ..writeString(obj.date);
  }
}

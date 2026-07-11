import 'revv_route.dart';
import 'run_telemetry_detail.dart';

/// 급조작 순간 — G포스가 임계값을 초과한 지점
class SharpCorner {
  final LatLng position;
  final double lateralG; // 횡G (절댓값)
  final double speedKmh;
  final String driveMode;
  final DateTime time;

  const SharpCorner({
    required this.position,
    required this.lateralG,
    this.speedKmh = 0,
    this.driveMode = 'cruise',
    required this.time,
  });

  Map<String, dynamic> toJson() => {
    'lat': position.lat,
    'lng': position.lng,
    'lateralG': lateralG,
    'speedKmh': speedKmh,
    'driveMode': driveMode,
    'time': time.toIso8601String(),
  };

  factory SharpCorner.fromJson(Map<String, dynamic> json) {
    return SharpCorner(
      position: LatLng(
        (json['lat'] as num).toDouble(),
        (json['lng'] as num).toDouble(),
      ),
      lateralG: (json['lateralG'] as num).toDouble(),
      speedKmh: (json['speedKmh'] as num?)?.toDouble() ?? 0,
      driveMode: json['driveMode'] as String? ?? 'cruise',
      time: DateTime.parse(json['time'] as String),
    );
  }
}

class RunRecoverySnapshot {
  final DateTime startTime;
  final String? routeId;
  final String? routeName;
  final List<LatLng> gpsPath;
  final double distanceKm;
  final double maxSpeedKmh;
  final double totalSpeedSum;
  final int speedSamples;
  final Map<String, int> driveModeSeconds;
  final List<SharpCorner> sharpCorners;
  final List<TelemetrySample> telemetrySamples;
  final String weatherEmoji;
  final String tempDisplay;
  final String weatherDesc;
  final DateTime lastSampleTime;

  const RunRecoverySnapshot({
    required this.startTime,
    this.routeId,
    this.routeName,
    required this.gpsPath,
    required this.distanceKm,
    required this.maxSpeedKmh,
    required this.totalSpeedSum,
    required this.speedSamples,
    required this.driveModeSeconds,
    required this.sharpCorners,
    required this.telemetrySamples,
    required this.weatherEmoji,
    required this.tempDisplay,
    required this.weatherDesc,
    required this.lastSampleTime,
  });

  Map<String, dynamic> toJson() => {
    'startTime': startTime.toIso8601String(),
    if (routeId != null) 'routeId': routeId,
    if (routeName != null) 'routeName': routeName,
    'gpsPath': gpsPath
        .map((point) => {'lat': point.lat, 'lng': point.lng})
        .toList(),
    'distanceKm': distanceKm,
    'maxSpeedKmh': maxSpeedKmh,
    'totalSpeedSum': totalSpeedSum,
    'speedSamples': speedSamples,
    'driveModeSeconds': driveModeSeconds,
    'sharpCorners': sharpCorners.map((corner) => corner.toJson()).toList(),
    'telemetrySamples': telemetrySamples
        .map((sample) => sample.toJson())
        .toList(),
    'weatherEmoji': weatherEmoji,
    'tempDisplay': tempDisplay,
    'weatherDesc': weatherDesc,
    'lastSampleTime': lastSampleTime.toIso8601String(),
  };

  factory RunRecoverySnapshot.fromJson(Map<String, dynamic> json) {
    return RunRecoverySnapshot(
      startTime: DateTime.parse(json['startTime'] as String),
      routeId: json['routeId'] as String?,
      routeName: json['routeName'] as String?,
      gpsPath: (json['gpsPath'] as List)
          .map(
            (item) => LatLng(
              ((item as Map)['lat'] as num).toDouble(),
              (item['lng'] as num).toDouble(),
            ),
          )
          .toList(),
      distanceKm: (json['distanceKm'] as num).toDouble(),
      maxSpeedKmh: (json['maxSpeedKmh'] as num).toDouble(),
      totalSpeedSum: (json['totalSpeedSum'] as num).toDouble(),
      speedSamples: (json['speedSamples'] as num).toInt(),
      driveModeSeconds: (json['driveModeSeconds'] as Map).map(
        (key, value) => MapEntry(key.toString(), (value as num).toInt()),
      ),
      sharpCorners: (json['sharpCorners'] as List)
          .map(
            (item) =>
                SharpCorner.fromJson((item as Map).cast<String, dynamic>()),
          )
          .toList(),
      telemetrySamples: (json['telemetrySamples'] as List)
          .map(
            (item) =>
                TelemetrySample.fromJson((item as Map).cast<String, dynamic>()),
          )
          .toList(),
      weatherEmoji: json['weatherEmoji'] as String,
      tempDisplay: json['tempDisplay'] as String,
      weatherDesc: json['weatherDesc'] as String,
      lastSampleTime: DateTime.parse(json['lastSampleTime'] as String),
    );
  }

  RunSession toRunSession() {
    final id = routeId;
    final name = routeName;
    final route = id == null && name == null
        ? null
        : RevvRoute(
            id: id ?? '',
            name: name ?? '',
            nodes: gpsPath,
            distanceKm: 0,
            windingScore: 0,
            starRating: 0,
            sharpCurveCount: 0,
            centerPoint: gpsPath.isEmpty ? const LatLng(0, 0) : gpsPath.first,
            distanceFromUser: 0,
          );
    return RunSession(
      startTime: startTime,
      endTime: lastSampleTime,
      maxSpeedKmh: maxSpeedKmh,
      avgSpeedKmh: speedSamples == 0 ? 0 : totalSpeedSum / speedSamples,
      distanceKm: distanceKm,
      gpsPath: List.unmodifiable(gpsPath),
      route: route,
      weatherEmoji: weatherEmoji,
      tempDisplay: tempDisplay,
      weatherDesc: weatherDesc,
      driveModeSeconds: Map.unmodifiable(driveModeSeconds),
      sharpCorners: List.unmodifiable(sharpCorners),
      telemetrySamples: List.unmodifiable(telemetrySamples),
    );
  }
}

class RunSession {
  final DateTime startTime;
  final DateTime endTime;
  final double maxSpeedKmh;
  final double avgSpeedKmh;
  final double distanceKm;
  final List<LatLng> gpsPath;
  final RevvRoute? route;
  final String weatherEmoji;
  final String tempDisplay;
  final String weatherDesc;

  /// IMU 최대 횡G (에뮬레이터에서는 0.0)
  final double maxLateralG;

  /// IMU 최대 종G (에뮬레이터에서는 0.0)
  final double maxLonG;

  /// DriveMode별 누적 초 {'cruise': 120, 'winding': 45, 'sport': 30}
  final Map<String, int> driveModeSeconds;

  /// G포스 임계값(0.45G) 초과 급조작 지점 목록
  final List<SharpCorner> sharpCorners;
  final List<TelemetrySample> telemetrySamples;

  const RunSession({
    required this.startTime,
    required this.endTime,
    required this.maxSpeedKmh,
    required this.avgSpeedKmh,
    required this.distanceKm,
    required this.gpsPath,
    this.route,
    required this.weatherEmoji,
    required this.tempDisplay,
    required this.weatherDesc,
    this.maxLateralG = 0.0,
    this.maxLonG = 0.0,
    this.driveModeSeconds = const {},
    this.sharpCorners = const [],
    this.telemetrySamples = const [],
  });

  Duration get duration => endTime.difference(startTime);

  String get durationDisplay {
    final d = duration;
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    if (m > 0) return '${m}m ${s.toString().padLeft(2, '0')}s';
    return '${s}s';
  }

  String get routeName => route?.name ?? '자유 드라이빙';
}

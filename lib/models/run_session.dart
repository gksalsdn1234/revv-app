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

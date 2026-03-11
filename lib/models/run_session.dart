import 'revv_route.dart';

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

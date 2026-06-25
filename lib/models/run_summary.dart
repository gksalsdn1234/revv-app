import 'dart:convert';
import 'revv_route.dart';

class RunSummary {
  final String id;
  final DateTime date;
  final double distanceKm;
  final int durationSeconds;
  final double maxSpeedKmh;
  final double avgSpeedKmh;
  final String routeName;
  final String? routeId;
  final String weatherEmoji;
  final String tempDisplay;

  /// IMU 최대 횡G — 실기기에서만 유효, 에뮬레이터는 0.0
  final double? maxLateralG;
  final double? maxLongitudinalG;

  /// 급조작 횟수 (G > 0.45G 순간) — 실기기에서만 유효
  final int sharpCornersCount;
  final int telemetrySampleCount;
  final int windingSeconds;
  final int sportSeconds;
  final double? routeDistanceKm;
  final int? routeCompletionPct;
  final LatLng? startPoint;
  final LatLng? endPoint;

  const RunSummary({
    required this.id,
    required this.date,
    required this.distanceKm,
    required this.durationSeconds,
    this.maxSpeedKmh = 0,
    this.avgSpeedKmh = 0,
    required this.routeName,
    this.routeId,
    required this.weatherEmoji,
    required this.tempDisplay,
    this.maxLateralG,
    this.maxLongitudinalG,
    this.sharpCornersCount = 0,
    this.telemetrySampleCount = 0,
    this.windingSeconds = 0,
    this.sportSeconds = 0,
    this.routeDistanceKm,
    this.routeCompletionPct,
    this.startPoint,
    this.endPoint,
  });

  double? get peakG {
    final lateral = maxLateralG?.abs() ?? 0;
    final longitudinal = maxLongitudinalG?.abs() ?? 0;
    final peak = lateral > longitudinal ? lateral : longitudinal;
    return peak > 0 ? peak : null;
  }

  String get durationDisplay {
    final h = durationSeconds ~/ 3600;
    final m = (durationSeconds % 3600) ~/ 60;
    final s = durationSeconds % 60;
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    if (m > 0) return '${m}m ${s.toString().padLeft(2, '0')}s';
    return '${s}s';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'date': date.toIso8601String(),
    'distanceKm': distanceKm,
    'durationSeconds': durationSeconds,
    if (maxSpeedKmh > 0) 'maxSpeedKmh': maxSpeedKmh,
    if (avgSpeedKmh > 0) 'avgSpeedKmh': avgSpeedKmh,
    'routeName': routeName,
    'routeId': routeId,
    'weatherEmoji': weatherEmoji,
    'tempDisplay': tempDisplay,
    if (maxLateralG != null) 'maxLateralG': maxLateralG,
    if (maxLongitudinalG != null) 'maxLongitudinalG': maxLongitudinalG,
    if (sharpCornersCount > 0) 'sharpCornersCount': sharpCornersCount,
    if (telemetrySampleCount > 0) 'telemetrySampleCount': telemetrySampleCount,
    if (windingSeconds > 0) 'windingSeconds': windingSeconds,
    if (sportSeconds > 0) 'sportSeconds': sportSeconds,
    if (routeDistanceKm != null) 'routeDistanceKm': routeDistanceKm,
    if (routeCompletionPct != null) 'routeCompletionPct': routeCompletionPct,
    if (startPoint != null)
      'startPoint': {'lat': startPoint!.lat, 'lng': startPoint!.lng},
    if (endPoint != null)
      'endPoint': {'lat': endPoint!.lat, 'lng': endPoint!.lng},
  };

  factory RunSummary.fromJson(Map<String, dynamic> j) => RunSummary(
    id: j['id'] as String,
    date: DateTime.parse(j['date'] as String),
    distanceKm: (j['distanceKm'] as num).toDouble(),
    durationSeconds: j['durationSeconds'] as int,
    maxSpeedKmh: (j['maxSpeedKmh'] as num?)?.toDouble() ?? 0,
    avgSpeedKmh: (j['avgSpeedKmh'] as num?)?.toDouble() ?? 0,
    routeName: j['routeName'] as String,
    routeId: j['routeId'] as String?,
    weatherEmoji: j['weatherEmoji'] as String,
    tempDisplay: j['tempDisplay'] as String,
    maxLateralG: (j['maxLateralG'] as num?)?.toDouble(),
    maxLongitudinalG: (j['maxLongitudinalG'] as num?)?.toDouble(),
    sharpCornersCount: (j['sharpCornersCount'] as int?) ?? 0,
    telemetrySampleCount: (j['telemetrySampleCount'] as num?)?.toInt() ?? 0,
    windingSeconds: (j['windingSeconds'] as num?)?.toInt() ?? 0,
    sportSeconds: (j['sportSeconds'] as num?)?.toInt() ?? 0,
    routeDistanceKm: (j['routeDistanceKm'] as num?)?.toDouble(),
    routeCompletionPct: (j['routeCompletionPct'] as num?)?.toInt(),
    startPoint: _latLngFromJson(j['startPoint']),
    endPoint: _latLngFromJson(j['endPoint']),
  );

  static LatLng? _latLngFromJson(dynamic value) {
    if (value is! Map<String, dynamic>) return null;
    final lat = value['lat'];
    final lng = value['lng'];
    if (lat is! num || lng is! num) return null;
    return LatLng(lat.toDouble(), lng.toDouble());
  }

  static List<RunSummary> listFromJson(String raw) {
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => RunSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static String listToJson(List<RunSummary> items) =>
      jsonEncode(items.map((e) => e.toJson()).toList());
}

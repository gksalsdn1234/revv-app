import 'revv_route.dart';
import 'run_session.dart';

class TelemetrySample {
  final int tMs;
  final double lat;
  final double lng;
  final double speedKmh;
  final double lateralG;
  final double longitudinalG;
  final String driveMode;

  const TelemetrySample({
    required this.tMs,
    required this.lat,
    required this.lng,
    required this.speedKmh,
    required this.lateralG,
    required this.longitudinalG,
    required this.driveMode,
  });

  Map<String, dynamic> toJson() => {
    'tMs': tMs,
    'lat': lat,
    'lng': lng,
    'speedKmh': speedKmh,
    'lateralG': lateralG,
    'longitudinalG': longitudinalG,
    'driveMode': driveMode,
  };

  factory TelemetrySample.fromJson(Map<String, dynamic> json) {
    return TelemetrySample(
      tMs: (json['tMs'] as num).toInt(),
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      speedKmh: (json['speedKmh'] as num?)?.toDouble() ?? 0,
      lateralG: (json['lateralG'] as num?)?.toDouble() ?? 0,
      longitudinalG: (json['longitudinalG'] as num?)?.toDouble() ?? 0,
      driveMode: json['driveMode'] as String? ?? 'cruise',
    );
  }
}

class RunTelemetryDetail {
  static const currentVersion = 2;

  final String runId;
  final int version;
  final Map<String, dynamic>? routeSnapshot;
  final List<TelemetrySample> samples;
  final List<Map<String, dynamic>> sharpEvents;
  final Map<String, dynamic> analytics;
  final Map<String, int> driveModeSeconds;
  final Map<String, dynamic> weather;
  final DateTime createdAt;

  const RunTelemetryDetail({
    required this.runId,
    required this.version,
    required this.routeSnapshot,
    required this.samples,
    required this.sharpEvents,
    this.analytics = const {},
    required this.driveModeSeconds,
    required this.weather,
    required this.createdAt,
  });

  factory RunTelemetryDetail.fromSession(String runId, RunSession session) {
    return RunTelemetryDetail(
      runId: runId,
      version: currentVersion,
      routeSnapshot: _routeSnapshot(session.route),
      samples: session.telemetrySamples,
      sharpEvents: session.sharpCorners
          .map(
            (event) => {
              'lat': event.position.lat,
              'lng': event.position.lng,
              'lateralG': event.lateralG,
              'speedKmh': event.speedKmh,
              'driveMode': event.driveMode,
              'time': event.time.toIso8601String(),
            },
          )
          .toList(),
      analytics: _analytics(session),
      driveModeSeconds: Map.of(session.driveModeSeconds),
      weather: {
        'emoji': session.weatherEmoji,
        'tempDisplay': session.tempDisplay,
        'description': session.weatherDesc,
      },
      createdAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'runId': runId,
    'version': version,
    'routeSnapshot': routeSnapshot,
    'samples': samples.map((sample) => sample.toJson()).toList(),
    'sharpEvents': sharpEvents,
    if (analytics.isNotEmpty) 'analytics': analytics,
    'driveModeSeconds': driveModeSeconds,
    'weather': weather,
    'createdAt': createdAt.toIso8601String(),
  };

  factory RunTelemetryDetail.fromJson(Map<String, dynamic> json) {
    return RunTelemetryDetail(
      runId: json['runId'] as String,
      version: (json['version'] as num?)?.toInt() ?? currentVersion,
      routeSnapshot: (json['routeSnapshot'] as Map?)?.cast<String, dynamic>(),
      samples:
          (json['samples'] as List?)
              ?.whereType<Map>()
              .map((item) => TelemetrySample.fromJson(item.cast()))
              .toList() ??
          const [],
      sharpEvents:
          (json['sharpEvents'] as List?)
              ?.whereType<Map>()
              .map((item) => item.cast<String, dynamic>())
              .toList() ??
          const [],
      analytics:
          (json['analytics'] as Map?)?.cast<String, dynamic>() ?? const {},
      driveModeSeconds:
          (json['driveModeSeconds'] as Map?)?.map(
            (key, value) => MapEntry(key.toString(), (value as num).toInt()),
          ) ??
          const {},
      weather: (json['weather'] as Map?)?.cast<String, dynamic>() ?? const {},
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  static Map<String, dynamic>? _routeSnapshot(RevvRoute? route) {
    if (route == null) return null;
    return {
      'id': route.id,
      'name': route.name,
      'distanceKm': route.distanceKm,
      'windingScore': route.windingScore,
      'starRating': route.starRating,
      'sharpCurveCount': route.sharpCurveCount,
      'mediumCurveKm': route.mediumCurveKm,
      'tightCurveKm': route.tightCurveKm,
      'maxContinuousKm': route.maxContinuousKm,
      'flowScore': route.flowScore,
      'curveStyle': route.curveStyle,
      'routeCharacter': route.routeCharacter,
      'stopSignCount': route.stopSignCount,
      'trafficSignalCount': route.trafficSignalCount,
      'elevationDelta': route.elevationDelta,
      'isLoop': route.isLoop,
      'nodes': route.nodes
          .map((node) => {'lat': node.lat, 'lng': node.lng})
          .toList(),
    };
  }

  static Map<String, dynamic> _analytics(RunSession session) {
    final samples = session.telemetrySamples;
    final movingSamples = samples.where((s) => s.speedKmh >= 3).toList();
    final absLatG = samples.map((s) => s.lateralG.abs()).toList()..sort();
    final absLonG = samples.map((s) => s.longitudinalG.abs()).toList()..sort();
    final brakingEvents = samples
        .where((s) => s.longitudinalG <= -0.30 && s.speedKmh >= 8)
        .length;
    final accelerationEvents = samples
        .where((s) => s.longitudinalG >= 0.25 && s.speedKmh >= 8)
        .length;
    final windingSamples = samples
        .where((s) => s.lateralG.abs() >= 0.18 && s.speedKmh >= 12)
        .length;
    final routeDistance = session.route?.distanceKm;

    return {
      'sampleCount': samples.length,
      'movingSampleCount': movingSamples.length,
      'durationSeconds': session.duration.inSeconds,
      'distanceKm': session.distanceKm,
      'routeDistanceKm': routeDistance,
      if (routeDistance != null && routeDistance > 0)
        'routeCompletionPct': (session.distanceKm / routeDistance * 100).clamp(
          0.0,
          999.0,
        ),
      'maxSpeedKmh': session.maxSpeedKmh,
      'avgSpeedKmh': session.avgSpeedKmh,
      'avgMovingSpeedKmh': _avg(movingSamples.map((s) => s.speedKmh)),
      'maxLateralG': session.maxLateralG,
      'maxLongitudinalG': session.maxLonG,
      'peakG': session.maxLateralG.abs() >= session.maxLonG.abs()
          ? session.maxLateralG.abs()
          : session.maxLonG.abs(),
      'avgAbsLateralG': _avg(absLatG),
      'p95AbsLateralG': _percentile(absLatG, 0.95),
      'avgAbsLongitudinalG': _avg(absLonG),
      'p95AbsLongitudinalG': _percentile(absLonG, 0.95),
      'sharpEventCount': session.sharpCorners.length,
      'brakingEventCount': brakingEvents,
      'accelerationEventCount': accelerationEvents,
      'windingSampleCount': windingSamples,
      'windingSamplePct': samples.isEmpty
          ? 0
          : (windingSamples / samples.length * 100),
      'driveModeSeconds': Map.of(session.driveModeSeconds),
      'speedBuckets': _speedBuckets(samples),
    };
  }

  static double _avg(Iterable<double> values) {
    var sum = 0.0;
    var count = 0;
    for (final value in values) {
      sum += value;
      count++;
    }
    return count == 0 ? 0 : sum / count;
  }

  static double _percentile(List<double> sortedValues, double percentile) {
    if (sortedValues.isEmpty) return 0;
    final index = ((sortedValues.length - 1) * percentile).round();
    return sortedValues[index.clamp(0, sortedValues.length - 1)];
  }

  static Map<String, int> _speedBuckets(List<TelemetrySample> samples) {
    final buckets = {'0_30': 0, '30_60': 0, '60_90': 0, '90_plus': 0};
    for (final sample in samples) {
      if (sample.speedKmh < 30) {
        buckets['0_30'] = buckets['0_30']! + 1;
      } else if (sample.speedKmh < 60) {
        buckets['30_60'] = buckets['30_60']! + 1;
      } else if (sample.speedKmh < 90) {
        buckets['60_90'] = buckets['60_90']! + 1;
      } else {
        buckets['90_plus'] = buckets['90_plus']! + 1;
      }
    }
    return buckets;
  }
}

import 'revv_route.dart';
import 'run_session.dart';

part '_run_telemetry_event_analysis.dart';

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
  static const currentVersion = 3;

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

  static Map<String, dynamic> _analytics(RunSession session) {
    final samples = session.telemetrySamples;
    final eventAnalysis = _telemetryEventAnalysis(samples);
    final smoothedSamples = eventAnalysis.smoothedSamples;
    final movingSamples = samples.where((s) => s.speedKmh >= 3).toList();
    final absLatG = smoothedSamples.map((s) => s.lateralG.abs()).toList()
      ..sort();
    final absLonG = smoothedSamples.map((s) => s.longitudinalG.abs()).toList()
      ..sort();
    final routeDistance = session.route?.distanceKm;
    final sampleCount = samples.length;
    final movingSampleCount = movingSamples.length;
    final durationSeconds = session.duration.inSeconds;
    final movingDurationSeconds =
        (durationSeconds * _ratio(movingSampleCount, sampleCount)).round();
    final idleDurationSeconds = durationSeconds - movingDurationSeconds;
    final p95AbsLateralG = _percentile(absLatG, 0.95);
    final p95AbsLongitudinalG = _percentile(absLonG, 0.95);
    final sharpEventCount = samples.isEmpty
        ? session.sharpCorners.length
        : eventAnalysis.sharpEventCount;
    final windingSamplePct = sampleCount == 0
        ? 0.0
        : eventAnalysis.windingSampleCount / sampleCount * 100;
    final brakingEventsPer10Min = _ratio(
      eventAnalysis.brakingEventCount * 600,
      durationSeconds,
    );
    final accelerationEventsPer10Min = _ratio(
      eventAnalysis.accelerationEventCount * 600,
      durationSeconds,
    );
    final movingSampleRatio = _ratio(movingSampleCount, sampleCount);
    final windingSeconds = session.driveModeSeconds['winding'] ?? 0;
    final technicalScore = _clampedScore(
      40 * _ratio(session.route?.tightCurveKm ?? 0, 2.5) +
          30 * _ratio(session.route?.mediumCurveKm ?? 0, 5.0) +
          30 * _ratio(p95AbsLateralG > 0.45 ? 0.45 : p95AbsLateralG, 0.45),
    );
    final smoothnessScore = _clampedScore(
      100 -
          35 * _ratio(brakingEventsPer10Min, 8) -
          25 * _ratio(accelerationEventsPer10Min, 8) -
          25 * _ratio(p95AbsLongitudinalG, 0.40) -
          15 * _ratio(sharpEventCount, 6),
    );
    final flowScoreDisplay = _clampedScore(
      40 * _ratio(session.route?.maxContinuousKm ?? 0, 4.0) +
          25 * movingSampleRatio +
          20 * _ratio(windingSeconds, durationSeconds) +
          15 * (1 - _ratio(idleDurationSeconds, durationSeconds)),
    );
    final revvScore = _clampedScore(
      0.30 * windingSamplePct +
          0.25 * flowScoreDisplay +
          0.25 * smoothnessScore +
          0.20 * technicalScore,
    );

    return {
      'sampleCount': sampleCount,
      'movingSampleCount': movingSampleCount,
      'durationSeconds': durationSeconds,
      'movingDurationSeconds': movingDurationSeconds,
      'idleDurationSeconds': idleDurationSeconds,
      'distanceKm': session.distanceKm,
      'gpsPointCount': session.gpsPath.length,
      'routeDistanceKm': routeDistance,
      'routeCompletionPct': routeDistance != null && routeDistance > 0
          ? (session.distanceKm / routeDistance * 100).clamp(0.0, 999.0)
          : 0,
      'maxSpeedKmh': session.maxSpeedKmh,
      'avgSpeedKmh': session.avgSpeedKmh,
      'avgMovingSpeedKmh': _avg(movingSamples.map((s) => s.speedKmh)),
      'maxLateralG': session.maxLateralG,
      'maxLongitudinalG': session.maxLonG,
      'peakG': session.maxLateralG.abs() >= session.maxLonG.abs()
          ? session.maxLateralG.abs()
          : session.maxLonG.abs(),
      'avgAbsLateralG': _avg(absLatG),
      'p95AbsLateralG': p95AbsLateralG,
      'avgAbsLongitudinalG': _avg(absLonG),
      'p95AbsLongitudinalG': p95AbsLongitudinalG,
      'sharpEventCount': sharpEventCount,
      'brakingEventCount': eventAnalysis.brakingEventCount,
      'accelerationEventCount': eventAnalysis.accelerationEventCount,
      'windingSampleCount': eventAnalysis.windingSampleCount,
      'windingSamplePct': windingSamplePct,
      'technicalScore': technicalScore,
      'smoothnessScore': smoothnessScore,
      'flowScoreDisplay': flowScoreDisplay,
      'revvScore': revvScore,
      'driveModeSeconds': Map.of(session.driveModeSeconds),
      'speedBuckets': _speedBuckets(samples),
    };
  }

  static int _clampedScore(num value) {
    return value.round().clamp(0, 100).toInt();
  }

  static double _ratio(num numerator, num denominator) {
    return denominator == 0 ? 0 : numerator / denominator;
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
}

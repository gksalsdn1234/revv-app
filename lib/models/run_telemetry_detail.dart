import 'obd_data.dart';
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
  static const currentVersion = 1;

  final String runId;
  final int version;
  final Map<String, dynamic>? routeSnapshot;
  final List<TelemetrySample> samples;
  final List<Map<String, dynamic>> sharpEvents;
  final Map<String, int> driveModeSeconds;
  final OBDRunSummary? obdSummary;
  final Map<String, dynamic> weather;
  final DateTime createdAt;

  const RunTelemetryDetail({
    required this.runId,
    required this.version,
    required this.routeSnapshot,
    required this.samples,
    required this.sharpEvents,
    required this.driveModeSeconds,
    required this.obdSummary,
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
              'time': event.time.toIso8601String(),
            },
          )
          .toList(),
      driveModeSeconds: Map.of(session.driveModeSeconds),
      obdSummary: session.obdSummary,
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
    'driveModeSeconds': driveModeSeconds,
    if (obdSummary?.hasData == true) 'obdSummary': obdSummary!.toJson(),
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
      driveModeSeconds:
          (json['driveModeSeconds'] as Map?)?.map(
            (key, value) => MapEntry(key.toString(), (value as num).toInt()),
          ) ??
          const {},
      obdSummary: json['obdSummary'] is Map
          ? OBDRunSummary.fromJson(
              (json['obdSummary'] as Map).cast<String, dynamic>(),
            )
          : null,
      weather:
          (json['weather'] as Map?)?.cast<String, dynamic>() ??
          const {},
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
      'nodes': route.nodes
          .map((node) => {'lat': node.lat, 'lng': node.lng})
          .toList(),
    };
  }
}

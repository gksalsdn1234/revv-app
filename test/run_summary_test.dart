import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/core/storage_keys.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/models/run_session.dart';
import 'package:revv_app/models/run_summary.dart';
import 'package:revv_app/models/run_telemetry_detail.dart';
import 'package:revv_app/services/run_history_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('run summary round-trips compact ride metrics', () async {
    SharedPreferences.setMockInitialValues({
      StorageKeys.cloudRunStorageEnabled: false,
    });
    final session = _session();
    final analytics = RunTelemetryDetail.fromSession(
      'expected-run',
      session,
    ).analytics;

    final summary = await RunHistoryService().save(session);
    final json = summary.toJson();
    final restored = RunSummary.fromJson(json);

    expect(restored.revvScore, analytics['revvScore']);
    expect(restored.windingSamplePct, analytics['windingSamplePct']);
    expect(
      restored.p95LateralG,
      closeTo((analytics['p95AbsLateralG'] as num).toDouble(), 0.0001),
    );
    expect(restored.brakingEventCount, analytics['brakingEventCount']);
    expect(
      restored.accelerationEventCount,
      analytics['accelerationEventCount'],
    );
    expect(restored.smoothnessScore, analytics['smoothnessScore']);
    expect(restored.routeCompletionPct, analytics['routeCompletionPct']);
    expect(json.keys, isNot(contains('analytics')));
    expect(json.keys, isNot(contains('samples')));
    expect(json.keys, isNot(contains('speedBuckets')));
  });

  test('run summary loads old json without rich metrics', () {
    final summary = RunSummary.fromJson({
      'id': 'old-run',
      'date': '2026-04-01T10:00:00Z',
      'distanceKm': 10.5,
      'durationSeconds': 900,
      'routeName': 'Old Route',
      'weatherEmoji': 'clear',
      'tempDisplay': '18 C',
    });

    expect(summary.revvScore, isNull);
    expect(summary.windingSamplePct, isNull);
    expect(summary.p95LateralG, isNull);
    expect(summary.brakingEventCount, 0);
    expect(summary.accelerationEventCount, 0);
    expect(summary.smoothnessScore, isNull);
    expect(summary.routeCompletionPct, isNull);
  });
}

RunSession _session() {
  final startedAt = DateTime.parse('2026-06-30T12:00:00Z');
  return RunSession(
    startTime: startedAt,
    endTime: startedAt.add(const Duration(minutes: 10)),
    maxSpeedKmh: 92,
    avgSpeedKmh: 48,
    distanceKm: 2.4,
    gpsPath: const [
      LatLng(45, -73),
      LatLng(45.01, -73.01),
      LatLng(45.02, -73.02),
    ],
    route: _route(),
    weatherEmoji: 'clear',
    tempDisplay: '18 C',
    weatherDesc: 'clear',
    maxLateralG: 0.32,
    maxLonG: -0.2,
    driveModeSeconds: const {'cruise': 60, 'winding': 40},
    telemetrySamples: const [
      TelemetrySample(
        tMs: 0,
        lat: 45,
        lng: -73,
        speedKmh: 40,
        lateralG: 0.3,
        longitudinalG: -0.7,
        driveMode: 'winding',
      ),
      TelemetrySample(
        tMs: 100,
        lat: 45.01,
        lng: -73.01,
        speedKmh: 45,
        lateralG: 0.3,
        longitudinalG: -0.7,
        driveMode: 'winding',
      ),
      TelemetrySample(
        tMs: 200,
        lat: 45.02,
        lng: -73.02,
        speedKmh: 50,
        lateralG: 0.3,
        longitudinalG: 0.6,
        driveMode: 'cruise',
      ),
      TelemetrySample(
        tMs: 300,
        lat: 45.03,
        lng: -73.03,
        speedKmh: 55,
        lateralG: 0.3,
        longitudinalG: 0.6,
        driveMode: 'cruise',
      ),
    ],
  );
}

RevvRoute _route() {
  return const RevvRoute(
    id: 'route-1',
    name: 'Forest Sweep',
    nodes: [LatLng(45, -73), LatLng(45.1, -73.1)],
    distanceKm: 5,
    windingScore: 4,
    starRating: 4,
    sharpCurveCount: 7,
    centerPoint: LatLng(45.05, -73.05),
    distanceFromUser: 3,
    tightCurveKm: 1,
    mediumCurveKm: 1,
    maxContinuousKm: 1,
  );
}

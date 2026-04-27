import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/models/obd_data.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/services/run_session_service.dart';
import 'package:revv_app/models/run_summary.dart';
import 'package:revv_app/models/run_telemetry_detail.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('run session keeps OBD summary when ending a drive', () {
    final service = RunSessionService();
    service.startSession(
      const RevvRoute(
        id: 'route-1',
        name: '테스트 루트',
        nodes: [LatLng(37.0, 127.0), LatLng(37.1, 127.1)],
        distanceKm: 12.3,
        windingScore: 4.0,
        starRating: 3,
        sharpCurveCount: 2,
        centerPoint: LatLng(37.05, 127.05),
        distanceFromUser: 3.0,
      ),
    );
    service.recordPosition(
      37.0,
      127.0,
      40,
      lateralG: 0.12,
      longitudinalG: 0.03,
      driveMode: 'cruise',
    );
    service.recordPosition(
      37.1,
      127.1,
      60,
      lateralG: 0.32,
      longitudinalG: 0.08,
      driveMode: 'winding',
    );

    const obd = OBDRunSummary(maxRpm: 4200, avgFuelRateLph: 6.5);
    final session = service.stopSession(
      maxLateralG: 0.42,
      maxLonG: 0.31,
      obdSummary: obd,
    );

    expect(session, isNotNull);
    expect(session!.obdSummary?.maxRpm, 4200);
    expect(session.maxLateralG, 0.42);
    expect(session.telemetrySamples, isNotEmpty);
    expect(session.telemetrySamples.last.driveMode, 'winding');
  });

  test('run telemetry detail serializes graph data', () {
    final service = RunSessionService();
    service.startSession(
      const RevvRoute(
        id: 'route-1',
        name: '테스트 루트',
        nodes: [LatLng(37.0, 127.0), LatLng(37.1, 127.1)],
        distanceKm: 12.3,
        windingScore: 4.0,
        starRating: 3,
        sharpCurveCount: 2,
        centerPoint: LatLng(37.05, 127.05),
        distanceFromUser: 3.0,
      ),
      weatherEmoji: '🌤',
      tempDisplay: '18°C',
      weatherDesc: '맑음',
    );
    service.recordPosition(
      37.0,
      127.0,
      40,
      lateralG: 0.11,
      longitudinalG: 0.02,
      driveMode: 'cruise',
    );
    service.recordSharpCorner(37.0, 127.0, 0.5);
    final session = service.stopSession(
      maxLateralG: 0.5,
      maxLonG: 0.2,
      obdSummary: const OBDRunSummary(maxRpm: 4200),
    );

    final detail = RunTelemetryDetail.fromSession('run-1', session!);
    final restored = RunTelemetryDetail.fromJson(detail.toJson());

    expect(restored.runId, 'run-1');
    expect(restored.samples.first.speedKmh, 40);
    expect(restored.samples.first.lateralG, 0.11);
    expect(restored.driveModeSeconds, isNotNull);
    expect(restored.sharpEvents, hasLength(1));
    expect(restored.obdSummary?.maxRpm, 4200);
    expect(restored.weather['tempDisplay'], '18°C');
    expect(restored.routeSnapshot?['id'], 'route-1');
  });

  test('run summary serializes optional route endpoints', () {
    final summary = RunSummary(
      id: 'run-1',
      date: DateTime.parse('2026-04-01T10:00:00Z'),
      distanceKm: 10.5,
      durationSeconds: 900,
      maxSpeedKmh: 72,
      avgSpeedKmh: 44,
      routeName: '자유 드라이빙',
      weatherEmoji: '🌤',
      tempDisplay: '18°C',
      sharpCornersCount: 1,
      startPoint: const LatLng(37.0, 127.0),
      endPoint: const LatLng(37.1, 127.1),
    );

    final restored = RunSummary.fromJson(summary.toJson());
    expect(restored.maxSpeedKmh, 72);
    expect(restored.avgSpeedKmh, 44);
    expect(restored.startPoint?.lat, 37.0);
    expect(restored.endPoint?.lng, 127.1);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:revv_app/core/storage_keys.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/models/run_session.dart';
import 'package:revv_app/models/run_telemetry_detail.dart';
import 'package:revv_app/screens/lean_run_summary_screen.dart';
import 'package:revv_app/services/run_history_service.dart';
import 'package:revv_app/services/run_session_service.dart';
import 'package:revv_app/services/settings_service.dart';
import 'package:revv_app/models/run_summary.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('run session records lean telemetry when ending a drive', () {
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

    final session = service.stopSession(maxLateralG: 0.42, maxLonG: 0.31);

    expect(session, isNotNull);
    expect(session!.maxLonG, 0.31);
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
    final session = service.stopSession(maxLateralG: 0.5, maxLonG: 0.2);

    final detail = RunTelemetryDetail.fromSession('run-1', session!);
    final json = detail.toJson();
    final restored = RunTelemetryDetail.fromJson(json);

    expect(restored.runId, 'run-1');
    expect(restored.samples.first.speedKmh, 40);
    expect(restored.samples.first.lateralG, 0.11);
    expect(restored.driveModeSeconds, isNotNull);
    expect(restored.sharpEvents, hasLength(1));
    expect(restored.sharpEvents.first['speedKmh'], 40);
    expect(restored.analytics['sampleCount'], 1);
    expect(restored.analytics['sharpEventCount'], 1);
    expect(restored.analytics['peakG'], 0.5);
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
      maxLongitudinalG: 0.3,
      sharpCornersCount: 1,
      telemetrySampleCount: 12,
      windingSeconds: 90,
      sportSeconds: 15,
      routeDistanceKm: 11,
      routeCompletionPct: 95,
      startPoint: const LatLng(37.0, 127.0),
      endPoint: const LatLng(37.1, 127.1),
    );

    final restored = RunSummary.fromJson(summary.toJson());
    expect(restored.maxSpeedKmh, 72);
    expect(restored.avgSpeedKmh, 44);
    expect(restored.maxLongitudinalG, 0.3);
    expect(restored.peakG, 0.3);
    expect(restored.telemetrySampleCount, 12);
    expect(restored.windingSeconds, 90);
    expect(restored.routeCompletionPct, 95);
    expect(restored.startPoint?.lat, 37.0);
    expect(restored.endPoint?.lng, 127.1);
  });

  testWidgets('run summary session log expands detailed sections', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      StorageKeys.cloudRunStorageEnabled: false,
    });
    await tester.binding.setSurfaceSize(const Size(800, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final startedAt = DateTime.parse('2026-04-01T10:00:00Z');
    final session = RunSession(
      startTime: startedAt,
      endTime: startedAt.add(const Duration(minutes: 8, seconds: 12)),
      maxSpeedKmh: 82,
      avgSpeedKmh: 46,
      distanceKm: 6.4,
      gpsPath: const [LatLng(37.0, 127.0)],
      route: const RevvRoute(
        id: 'route-1',
        name: '테스트 와인딩',
        nodes: [LatLng(37.0, 127.0), LatLng(37.1, 127.1)],
        distanceKm: 7.0,
        windingScore: 5.2,
        starRating: 4,
        sharpCurveCount: 5,
        centerPoint: LatLng(37.05, 127.05),
        distanceFromUser: 1.2,
      ),
      weatherEmoji: 'Clear',
      tempDisplay: '18C',
      weatherDesc: 'Clear',
      maxLateralG: 0.54,
      maxLonG: 0.31,
      driveModeSeconds: const {'cruise': 250, 'winding': 120},
      sharpCorners: [
        SharpCorner(
          position: const LatLng(37.01, 127.01),
          lateralG: 0.54,
          speedKmh: 48,
          driveMode: 'winding',
          time: startedAt.add(const Duration(minutes: 3)),
        ),
      ],
      telemetrySamples: const [
        TelemetrySample(
          tMs: 1000,
          lat: 37.0,
          lng: 127.0,
          speedKmh: 42,
          lateralG: 0.22,
          longitudinalG: -0.12,
          driveMode: 'cruise',
        ),
        TelemetrySample(
          tMs: 2000,
          lat: 37.01,
          lng: 127.01,
          speedKmh: 48,
          lateralG: 0.54,
          longitudinalG: -0.34,
          driveMode: 'winding',
        ),
      ],
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => RunHistoryService()),
          ChangeNotifierProvider(create: (_) => SettingsService()),
        ],
        child: MaterialApp(home: LeanRunSummaryScreen(session: session)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('SESSION LOG'), findsOneWidget);
    expect(find.text('Pace log'), findsOneWidget);
    expect(find.text('G-Force analysis'), findsOneWidget);
    expect(find.text('GPS POINTS'), findsOneWidget);

    await tester.tap(find.text('G-Force analysis'));
    await tester.pumpAndSettle();

    expect(find.text('MAX LAT G'), findsOneWidget);
    expect(find.text('0.54'), findsWidgets);
    expect(find.text('BRAKE / ACCEL'), findsOneWidget);
  });
}

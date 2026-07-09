import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:revv_app/core/storage_keys.dart';
import 'package:revv_app/core/app_language.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/models/run_session.dart';
import 'package:revv_app/models/run_telemetry_detail.dart';
import 'package:revv_app/screens/lean_home_screen.dart';
import 'package:revv_app/screens/lean_run_summary_screen.dart';
import 'package:revv_app/services/location_service.dart';
import 'package:revv_app/services/route_service.dart';
import 'package:revv_app/services/run_history_service.dart';
import 'package:revv_app/services/run_pending_upload_store.dart';
import 'package:revv_app/services/run_session_service.dart';
import 'package:revv_app/services/secure_session_store.dart';
import 'package:revv_app/services/settings_service.dart';
import 'package:revv_app/services/supabase_service.dart';
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
    expect(restored.analytics['sharpEventCount'], 0);
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

  testWidgets('settings profile uses run history instead of dummy data', (
    tester,
  ) async {
    final runs = [
      RunSummary(
        id: 'run-2',
        date: DateTime.parse('2026-05-02T10:00:00Z'),
        distanceKm: 7.2,
        durationSeconds: 600,
        maxSpeedKmh: 58,
        avgSpeedKmh: 42,
        routeName: 'Second run',
        weatherEmoji: '',
        tempDisplay: '',
      ),
      RunSummary(
        id: 'run-1',
        date: DateTime.parse('2026-03-15T10:00:00Z'),
        distanceKm: 5.1,
        durationSeconds: 500,
        maxSpeedKmh: 52,
        avgSpeedKmh: 38,
        routeName: 'First run',
        weatherEmoji: '',
        tempDisplay: '',
      ),
    ];
    SharedPreferences.setMockInitialValues({
      StorageKeys.runs: RunSummary.listToJson(runs),
    });
    await tester.binding.setSurfaceSize(const Size(800, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final history = RunHistoryService();
    await history.load();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<RunHistoryService>.value(value: history),
          ChangeNotifierProvider(create: (_) => SettingsService()),
          ChangeNotifierProvider(create: (_) => LocationService()),
          ChangeNotifierProvider(create: (_) => RouteService()),
          ChangeNotifierProvider.value(value: SupabaseService()),
        ],
        child: const MaterialApp(home: LeanHomeScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('JD'), findsNothing);
    expect(find.text('Driver #042'), findsNothing);
    expect(find.text('7 RUNS · MEMBER SINCE APR 2026'), findsNothing);
    expect(find.text('Anonymous driver'), findsOneWidget);
    expect(find.text('2 runs · since MAR 2026'), findsOneWidget);
  });

  testWidgets('home digest uses one CTA and cached nearby route cards', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(430, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final routeService = RouteService()
      ..routes = [
        _homeRoute('route-1', 'First Road', -73.0),
        _homeRoute('route-2', 'Second Road', -73.1),
        _homeRoute('route-3', 'Third Road', -73.2),
        _homeRoute('route-4', 'Fourth Road', -73.3),
      ];

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => RunHistoryService()),
          ChangeNotifierProvider(create: (_) => SettingsService()),
          ChangeNotifierProvider<LocationService>.value(
            value: _HomeLocationService(hasLocation: true),
          ),
          ChangeNotifierProvider<RouteService>.value(value: routeService),
          ChangeNotifierProvider.value(value: SupabaseService()),
        ],
        child: const MaterialApp(home: LeanHomeScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('FIND ROUTES'), findsOneWidget);
    expect(find.textContaining('Plan to destination'), findsNothing);
    expect(find.text('4 ROUTES NEARBY'), findsOneWidget);
    expect(find.text('NEARBY ROADS'), findsOneWidget);
    expect(find.text('First Road'), findsOneWidget);
    expect(find.text('Second Road'), findsOneWidget);
    expect(find.text('Third Road'), findsOneWidget);
    expect(find.text('Fourth Road'), findsNothing);
    expect(find.text('SYNCED'), findsNothing);

    await tester.tap(find.text('First Road'));
    await tester.pumpAndSettle();

    expect(find.textContaining('nearby routes'), findsWidgets);
    expect(routeService.selectedRoute?.id, 'route-1');
  });

  testWidgets('home digest shows placeholder and loading status correctly', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final routeService = RouteService()..isLoading = true;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => RunHistoryService()),
          ChangeNotifierProvider(create: (_) => SettingsService()),
          ChangeNotifierProvider<LocationService>.value(
            value: _HomeLocationService(hasLocation: false),
          ),
          ChangeNotifierProvider<RouteService>.value(value: routeService),
          ChangeNotifierProvider.value(value: SupabaseService()),
        ],
        child: const MaterialApp(home: LeanHomeScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Finding roads…'), findsOneWidget);
    expect(find.text('0 ROUTES NEARBY'), findsNothing);
    expect(find.text('Explore in Finder →'), findsOneWidget);
  });

  testWidgets('home digest recent run is one line and opens history', (
    tester,
  ) async {
    final runs = [
      RunSummary(
        id: 'run-1',
        date: DateTime.now().subtract(const Duration(hours: 2)),
        distanceKm: 12.4,
        durationSeconds: 900,
        maxSpeedKmh: 62,
        avgSpeedKmh: 43,
        routeName: 'Morning Pass',
        weatherEmoji: '',
        tempDisplay: '',
      ),
    ];
    SharedPreferences.setMockInitialValues({
      StorageKeys.runs: RunSummary.listToJson(runs),
    });
    final history = RunHistoryService();
    await history.load();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<RunHistoryService>.value(value: history),
          ChangeNotifierProvider(create: (_) => SettingsService()),
          ChangeNotifierProvider<LocationService>.value(
            value: _HomeLocationService(hasLocation: true),
          ),
          ChangeNotifierProvider(create: (_) => RouteService()),
          ChangeNotifierProvider.value(value: SupabaseService()),
        ],
        child: const MaterialApp(home: LeanHomeScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.textContaining('Last drive: Morning Pass · 12.4 km'),
      findsOneWidget,
    );
    expect(find.text('LAST DRIVE'), findsNothing);

    await tester.tap(find.textContaining('Last drive: Morning Pass'));
    await tester.pumpAndSettle();

    expect(find.text('HISTORY'), findsOneWidget);
    expect(find.text('Morning Pass'), findsWidgets);
  });

  testWidgets('home utilities move language and voice controls to settings', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService();
    final supabase = SupabaseService()
      ..debugSetCloudSessionStateForTesting(
        ready: true,
        uid: 'user-1',
        anonymous: false,
      );
    addTearDown(supabase.debugResetForTesting);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => RunHistoryService()),
          ChangeNotifierProvider<SettingsService>.value(value: settings),
          ChangeNotifierProvider<LocationService>.value(
            value: _HomeLocationService(hasLocation: true),
          ),
          ChangeNotifierProvider(create: (_) => RouteService()),
          ChangeNotifierProvider.value(value: supabase),
        ],
        child: const MaterialApp(home: LeanHomeScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('KO'), findsNothing);
    expect(find.text('FR'), findsNothing);
    expect(find.byIcon(Icons.volume_up_rounded), findsNothing);
    expect(find.text('SYNCED'), findsNothing);
    expect(find.text('LOCAL'), findsNothing);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Language'), findsOneWidget);
    expect(find.text('KO'), findsOneWidget);
    expect(find.text('EN'), findsOneWidget);
    expect(find.text('FR'), findsOneWidget);
    expect(find.text('Voice guidance'), findsOneWidget);

    await tester.tap(find.text('KO'));
    await tester.pumpAndSettle();

    expect(settings.appLanguage, AppLanguage.korean);
  });

  testWidgets('run summary session log expands detailed sections', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      StorageKeys.cloudRunStorageEnabled: false,
    });
    await tester.binding.setSurfaceSize(const Size(800, 4200));
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
        TelemetrySample(
          tMs: 3000,
          lat: 37.02,
          lng: 127.02,
          speedKmh: 49,
          lateralG: 0.50,
          longitudinalG: -0.33,
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
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('SESSION LOG'), findsOneWidget);
    expect(find.text('Pace log'), findsOneWidget);
    expect(find.text('Flow'), findsWidgets);
    expect(find.text('Smoothness'), findsWidgets);
    expect(find.text('Route context'), findsOneWidget);
    expect(find.text('Collection quality'), findsOneWidget);
    expect(find.text('Privacy & share'), findsOneWidget);
    expect(find.text('Handling notes'), findsOneWidget);
    expect(find.text('GPS POINTS'), findsWidgets);

    await tester.tap(find.text('Flow').last);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('FLOW SCORE'), findsOneWidget);
    expect(find.text('MOVING SAMPLES'), findsOneWidget);

    await tester.tap(find.text('Smoothness').last);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('SMOOTHNESS'), findsOneWidget);
    expect(find.text('BRAKE / ACCEL'), findsOneWidget);

    await tester.tap(find.text('Handling notes'));
    await tester.pumpAndSettle();

    expect(find.text('LAT G RANGE'), findsOneWidget);
    expect(find.text('0.54'), findsWidgets);

    await tester.tap(find.text('Route context'));
    await tester.pumpAndSettle();
    expect(find.text('ROUTE / DONE'), findsOneWidget);
    expect(find.text('ELEVATION'), findsOneWidget);

    await tester.tap(find.text('Weather & context'));
    await tester.pumpAndSettle();
    expect(find.text('WEATHER'), findsOneWidget);

    await tester.tap(find.text('Collection quality'));
    await tester.pumpAndSettle();
    expect(find.text('SAMPLES'), findsOneWidget);
    expect(find.text('GPS POINTS'), findsWidgets);

    await tester.tap(find.text('Privacy & share'));
    await tester.pumpAndSettle();
    expect(find.text('PUBLIC DEFAULT'), findsOneWidget);
    expect(find.text('Private speed data hidden'), findsOneWidget);
    expect(find.text('Raw coordinates hidden'), findsOneWidget);
    expect(find.textContaining('37.01000'), findsNothing);
    expect(find.textContaining('MAX SPEED'), findsNothing);
  });

  testWidgets('run summary recap shows share-ready ride metrics', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      StorageKeys.cloudRunStorageEnabled: false,
    });
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final startedAt = DateTime.parse('2026-04-01T10:00:00Z');
    final session = RunSession(
      startTime: startedAt,
      endTime: startedAt.add(const Duration(minutes: 8)),
      maxSpeedKmh: 118,
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
        tightCurveKm: 1.2,
        mediumCurveKm: 2.4,
        maxContinuousKm: 3.2,
      ),
      weatherEmoji: 'Clear',
      tempDisplay: '18C',
      weatherDesc: 'Clear',
      maxLateralG: 0.54,
      maxLonG: 0.31,
      driveModeSeconds: const {'cruise': 250, 'winding': 120},
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

    expect(find.text('REVV Recap'), findsOneWidget);
    expect(find.text('REVV Score'), findsOneWidget);
    expect(find.text('Winding'), findsOneWidget);
    expect(find.text('Flow'), findsWidgets);
    expect(find.text('Smoothness'), findsWidgets);
    expect(find.text('Distance'), findsOneWidget);
    expect(find.text('6.4 km'), findsWidgets);
    expect(find.textContaining('MAX SPEED'), findsNothing);
    expect(find.textContaining('118'), findsNothing);
  });

  testWidgets('run summary uses shared share metrics', (tester) async {
    SharedPreferences.setMockInitialValues({
      StorageKeys.cloudRunStorageEnabled: false,
    });

    final startedAt = DateTime.parse('2026-04-01T10:00:00Z');
    final session = RunSession(
      startTime: startedAt,
      endTime: startedAt.add(const Duration(minutes: 3)),
      maxSpeedKmh: 99,
      avgSpeedKmh: 35,
      distanceKm: 1.8,
      gpsPath: const [LatLng(37.0, 127.0)],
      route: const RevvRoute(
        id: 'route-2',
        name: 'Shared Metrics Route',
        nodes: [LatLng(37.0, 127.0), LatLng(37.02, 127.02)],
        distanceKm: 2.0,
        windingScore: 4,
        starRating: 3,
        sharpCurveCount: 2,
        centerPoint: LatLng(37.01, 127.01),
        distanceFromUser: 1,
      ),
      weatherEmoji: 'Clear',
      tempDisplay: '20C',
      weatherDesc: 'Clear',
      maxLateralG: 0.4,
      maxLonG: 0.2,
      sharpCorners: [
        SharpCorner(
          position: const LatLng(37.01, 127.01),
          lateralG: 0.4,
          driveMode: 'winding',
          time: startedAt.add(const Duration(minutes: 1)),
        ),
      ],
      telemetrySamples: const [
        TelemetrySample(
          tMs: 1000,
          lat: 37.0,
          lng: 127.0,
          speedKmh: 30,
          lateralG: 0.25,
          longitudinalG: 0.05,
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

    expect(find.text('Route'), findsOneWidget);
    expect(find.text('90% done'), findsOneWidget);
    expect(find.text('Corner events'), findsOneWidget);
  });

  testWidgets('run summary saves route feedback', (tester) async {
    SharedPreferences.setMockInitialValues({
      StorageKeys.cloudRunStorageEnabled: false,
    });
    await tester.binding.setSurfaceSize(const Size(800, 4200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final startedAt = DateTime.parse('2026-04-01T10:00:00Z');
    final session = RunSession(
      startTime: startedAt,
      endTime: startedAt.add(const Duration(minutes: 4)),
      maxSpeedKmh: 88,
      avgSpeedKmh: 36,
      distanceKm: 2.4,
      gpsPath: const [LatLng(37.0, 127.0)],
      route: const RevvRoute(
        id: 'route-feedback',
        name: 'Feedback Route',
        nodes: [LatLng(37.0, 127.0), LatLng(37.02, 127.02)],
        distanceKm: 3.0,
        windingScore: 4,
        starRating: 3,
        sharpCurveCount: 2,
        centerPoint: LatLng(37.01, 127.01),
        distanceFromUser: 1,
      ),
      weatherEmoji: 'Clear',
      tempDisplay: '20C',
      weatherDesc: 'Clear',
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

    await tester.ensureVisible(find.text('Flow broke'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Flow broke'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Privacy & share'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Privacy & share'));
    await tester.pumpAndSettle();

    expect(find.text('ROUTE FEEDBACK'), findsOneWidget);
    expect(find.text('Flow broke'), findsNWidgets(2));
    expect(
      (await SharedPreferences.getInstance()).getString(
        StorageKeys.routeFeedback,
      ),
      contains('flow_broken'),
    );
  });

  testWidgets('run history opens rich run report', (tester) async {
    final detailRun = RunSummary(
      id: 'detail-run',
      date: DateTime.parse('2026-04-01T10:00:00Z'),
      distanceKm: 7.4,
      durationSeconds: 540,
      avgSpeedKmh: 49,
      routeName: 'Detail Loaded Pass',
      weatherEmoji: 'Clear',
      tempDisplay: '18C',
      maxLateralG: 0.41,
      revvScore: 61,
      windingSamplePct: 44,
      p95LateralG: 0.37,
      brakingEventCount: 1,
      accelerationEventCount: 2,
      smoothnessScore: 78,
      routeCompletionPct: 93,
    );
    final summaryOnlyRun = RunSummary(
      id: 'summary-run',
      date: DateTime.parse('2026-04-02T10:00:00Z'),
      distanceKm: 5.2,
      durationSeconds: 420,
      avgSpeedKmh: 42,
      routeName: 'Summary Only Pass',
      weatherEmoji: 'Cloudy',
      tempDisplay: '16C',
      maxLateralG: 0.34,
      revvScore: 58,
      windingSamplePct: 39,
      p95LateralG: 0.31,
      brakingEventCount: 2,
      accelerationEventCount: 1,
      smoothnessScore: 74,
      routeCompletionPct: 88,
    );
    final detail = RunTelemetryDetail(
      runId: 'detail-run',
      version: RunTelemetryDetail.currentVersion,
      routeSnapshot: const {'id': 'route-detail', 'name': 'Detail Loaded Pass'},
      samples: const [],
      sharpEvents: const [],
      analytics: const {
        'revvScore': 73,
        'flowScoreDisplay': 82,
        'technicalScore': 66,
        'smoothnessScore': 79,
        'windingSamplePct': 47,
        'peakG': 0.43,
        'p95AbsLateralG': 0.38,
        'routeCompletionPct': 94,
        'sampleCount': 12,
        'gpsPointCount': 8,
      },
      driveModeSeconds: const {'winding': 180},
      weather: const {'tempDisplay': '18C'},
      createdAt: DateTime.parse('2026-04-01T10:09:00Z'),
    );
    SharedPreferences.setMockInitialValues({
      StorageKeys.cloudRunStorageEnabled: false,
      StorageKeys.runs: RunSummary.listToJson([summaryOnlyRun, detailRun]),
    });
    await tester.binding.setSurfaceSize(const Size(800, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final history = RunHistoryService(
      pendingStore: RunPendingUploadStore(
        detailStore: MemorySecureStringStore(),
      ),
    );
    await history.load();
    await history.saveDetail(detail);
    expect(await history.loadDetail('detail-run'), isNotNull);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: history),
          ChangeNotifierProvider(create: (_) => SettingsService()),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    backgroundColor: Colors.transparent,
                    isScrollControlled: true,
                    builder: (_) => const HistorySheet(),
                  ),
                  child: const Text('Open history'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Open history'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.ensureVisible(find.text('Summary Only Pass'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(
      find
          .ancestor(
            of: find.text('Summary Only Pass'),
            matching: find.byType(GestureDetector),
          )
          .first,
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(find.text('RUN REPORT'), findsOneWidget);
    expect(find.text('Summary Only Pass'), findsOneWidget);
    expect(find.text('REVV Score'), findsOneWidget);
    expect(find.text('58'), findsOneWidget);
    expect(find.text('Winding'), findsOneWidget);
    expect(find.text('39%'), findsOneWidget);
    expect(find.text('Summary only'), findsOneWidget);
    expect(find.textContaining('MAX SPEED'), findsNothing);

    Navigator.of(tester.element(find.text('RUN REPORT'))).pop();
    await tester.pump(const Duration(milliseconds: 350));

    await tester.tap(find.text('Open history'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.ensureVisible(find.text('Detail Loaded Pass'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(
      find
          .ancestor(
            of: find.text('Detail Loaded Pass'),
            matching: find.byType(GestureDetector),
          )
          .first,
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(find.text('RUN REPORT'), findsOneWidget);
    expect(find.text('Detail Loaded Pass'), findsOneWidget);
    expect(find.text('Detail loaded'), findsOneWidget);
  });

  testWidgets('run summary exposes share ride card action', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final file = File('${Directory.systemTemp.path}/revv-widget-share.png');
    var exportCalled = false;
    String? sharedPath;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => RunHistoryService()),
          ChangeNotifierProvider(create: (_) => SettingsService()),
        ],
        child: MaterialApp(
          home: LeanRunSummaryScreen.history(
            summary: _shareActionSummary(),
            detail: _shareActionDetail(),
            shareExporter: () {
              exportCalled = true;
              file.writeAsBytesSync([1, 2, 3], flush: true);
              return Future.value(file);
            },
            sharePresenter: (shared) async => sharedPath = shared.path,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Share ride card'), findsOneWidget);
    await tester.tap(find.text('Share ride card'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Share preview'), findsOneWidget);
    await tester.ensureVisible(find.text('Export card'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Export card'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(exportCalled, isTrue);
    expect(file.existsSync(), isTrue);
    // 내보내기 후 시스템 공유 시트로 파일이 전달돼야 한다
    expect(sharedPath, file.path);
  });

  testWidgets('share export failure is handled', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => RunHistoryService()),
          ChangeNotifierProvider(create: (_) => SettingsService()),
        ],
        child: MaterialApp(
          home: LeanRunSummaryScreen.history(
            summary: _shareActionSummary(),
            detail: _shareActionDetail(),
            shareExporter: () => throw StateError('export failed'),
            sharePresenter: (_) async {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Share ride card'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.ensureVisible(find.text('Export card'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Export card'));
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('Could not prepare share card'), findsOneWidget);
    expect(find.textContaining('export failed'), findsNothing);
  });

  testWidgets('run summary previews share card presets', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var exportCalled = false;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => RunHistoryService()),
          ChangeNotifierProvider(create: (_) => SettingsService()),
        ],
        child: MaterialApp(
          home: LeanRunSummaryScreen.history(
            summary: _shareActionSummary(),
            detail: _shareActionDetail(),
            shareExporter: () {
              exportCalled = true;
              return Future.value(
                File('${Directory.systemTemp.path}/revv-preview-share.png'),
              );
            },
            sharePresenter: (_) async {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Share ride card'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Share preview'), findsOneWidget);
    expect(find.text('Story'), findsOneWidget);
    expect(find.text('Square'), findsOneWidget);
    expect(find.text('Sticker'), findsOneWidget);
    expect(find.textContaining('Max speed'), findsNothing);
    expect(find.textContaining('MAX SPEED'), findsNothing);

    await tester.ensureVisible(find.text('Story'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Story'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.ensureVisible(find.text('Sticker'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Sticker'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.ensureVisible(find.text('Export card'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Export card'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(exportCalled, isTrue);
    expect(find.textContaining('Max speed'), findsNothing);
    expect(find.textContaining('MAX SPEED'), findsNothing);
  });
}

RunSummary _shareActionSummary() {
  return RunSummary(
    id: 'share-action-run',
    date: DateTime.parse('2026-04-01T10:00:00Z'),
    distanceKm: 8.8,
    durationSeconds: 742,
    maxSpeedKmh: 88,
    avgSpeedKmh: 43,
    routeName: 'Share Action Pass',
    routeId: 'share-route',
    weatherEmoji: 'Clear',
    tempDisplay: '18C',
    revvScore: 71,
    smoothnessScore: 77,
    windingSamplePct: 42,
    routeCompletionPct: 91,
  );
}

RunTelemetryDetail _shareActionDetail() {
  return RunTelemetryDetail(
    runId: 'share-action-run',
    version: RunTelemetryDetail.currentVersion,
    routeSnapshot: const {'id': 'share-route', 'name': 'Share Action Pass'},
    samples: const [
      TelemetrySample(
        tMs: 0,
        lat: 37.0,
        lng: 127.0,
        speedKmh: 42,
        lateralG: 0.18,
        longitudinalG: 0.04,
        driveMode: 'cruise',
      ),
      TelemetrySample(
        tMs: 1000,
        lat: 37.01,
        lng: 127.01,
        speedKmh: 48,
        lateralG: 0.34,
        longitudinalG: -0.12,
        driveMode: 'winding',
      ),
    ],
    analytics: const {
      'revvScore': 71,
      'flowScoreDisplay': 64,
      'technicalScore': 68,
      'smoothnessScore': 77,
      'windingSamplePct': 42,
      'routeCompletionPct': 91,
    },
    sharpEvents: const [],
    driveModeSeconds: const {'cruise': 1, 'winding': 1},
    weather: const {'tempDisplay': '18C'},
    createdAt: DateTime.parse('2026-04-01T10:12:00Z'),
  );
}

class _HomeLocationService extends LocationService {
  _HomeLocationService({required this.hasLocation}) {
    hasPermission = hasLocation;
  }

  final bool hasLocation;

  @override
  bool get hasBestKnownLocation => hasLocation;

  @override
  LatLng? get bestKnownLatLng => hasLocation ? const LatLng(45.0, -73.0) : null;

  @override
  Future<void> requestPermission() async {}

  @override
  Future<void> startTracking() async {}

  @override
  Future<LatLng?> ensureLiveLocation({
    Duration timeout = const Duration(seconds: 6),
  }) async => bestKnownLatLng;
}

RevvRoute _homeRoute(String id, String name, double lng) {
  return RevvRoute(
    id: id,
    name: name,
    nodes: [LatLng(45.0, lng), LatLng(45.02, lng - 0.02)],
    distanceKm: 8,
    windingScore: 6,
    starRating: 4,
    sharpCurveCount: 8,
    centerPoint: LatLng(45.01, lng - 0.01),
    distanceFromUser: 5,
    tightCurveKm: 1,
    mediumCurveKm: 1,
    maxContinuousKm: 1,
    routeRankScore: 6,
    flowScore: 1,
  );
}

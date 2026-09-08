import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/models/run_session.dart';
import 'package:revv_app/models/run_summary.dart';
import 'package:revv_app/models/run_telemetry_detail.dart';
import 'package:revv_app/screens/lean_app_shell_screen.dart';
import 'package:revv_app/services/driven_routes_service.dart';
import 'package:revv_app/services/location_service.dart';
import 'package:revv_app/services/route_service.dart';
import 'package:revv_app/services/run_history_service.dart';
import 'package:revv_app/services/run_recovery_store.dart';
import 'package:revv_app/services/run_session_service.dart';
import 'package:revv_app/services/settings_service.dart';
import 'package:revv_app/services/supabase_service.dart';
import 'package:revv_app/services/weather_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'snapshot writes only at 30 second boundaries and clears at ends',
    () async {
      var now = DateTime.parse('2026-07-11T10:00:00Z');
      final store = _FakeRecoveryStore();
      final service = RunSessionService(clock: () => now, recoveryStore: store);

      service.startSession(_route);
      await _flushAsync();
      expect(store.clearCount, 0);

      service.recordPosition(45, -73, 30);
      now = now.add(const Duration(seconds: 29));
      service.recordPosition(45.001, -73.001, 40);
      await _flushAsync();
      expect(store.writeCount, 0);

      now = now.add(const Duration(seconds: 1));
      service.recordPosition(45.002, -73.002, 50);
      await _flushAsync();
      expect(store.writeCount, 1);

      service.recordPosition(45.003, -73.003, 60);
      await _flushAsync();
      expect(store.writeCount, 1);

      now = now.add(const Duration(seconds: 30));
      service.recordPosition(45.004, -73.004, 70);
      await _flushAsync();
      expect(store.writeCount, 2);

      service.stopSession();
      await service.clearRecovery();
      await _flushAsync();
      expect(store.clearCount, 1);
    },
  );

  test(
    'snapshot write failure does not stop the drive or later writes',
    () async {
      var now = DateTime.parse('2026-07-11T10:00:00Z');
      final store = _FakeRecoveryStore(writeFailures: 1);
      final service = RunSessionService(clock: () => now, recoveryStore: store);
      service.startSession(_route);
      await _flushAsync();

      now = now.add(const Duration(seconds: 30));
      service.recordPosition(45, -73, 30);
      await _flushAsync();
      expect(service.isRecording, isTrue);

      now = now.add(const Duration(seconds: 30));
      service.recordPosition(45.001, -73.001, 40);
      await _flushAsync();
      expect(store.writeCount, 2);
      expect(store.snapshot, isNotNull);
    },
  );

  test('a one-second GPS teleport does not inflate run distance', () {
    var now = DateTime.parse('2026-07-11T10:00:00Z');
    final service = RunSessionService(clock: () => now)..startSession(_route);

    service.recordPosition(45, -73, 30);
    now = now.add(const Duration(seconds: 1));
    service.recordPosition(46, -74, 30);

    expect(service.currentDistance, lessThan(0.1));
  });

  test('snapshot round trip restores run values', () {
    final snapshot = _snapshot(distanceKm: 1.2);
    final restored = RunRecoverySnapshot.fromJson(snapshot.toJson());
    final session = restored.toRunSession();

    expect(session.runId, restored.toRunSession().runId);
    expect(session.distanceKm, 1.2);
    expect(session.gpsPath, hasLength(10));
    expect(session.driveModeSeconds, {'cruise': 20, 'winding': 10});
    expect(session.sharpCorners, hasLength(1));
    expect(session.endTime, snapshot.lastSampleTime);
    expect(session.avgSpeedKmh, 45);
  });

  test('invalid recovery JSON returns null without throwing', () async {
    final directory = await Directory.systemTemp.createTemp('revv-recovery');
    addTearDown(() => directory.delete(recursive: true));
    final store = RunRecoveryStore(directoryProvider: () async => directory);
    await File('${directory.path}/run_recovery.json').writeAsString('{invalid');

    expect(await store.readSnapshot(), isNull);
  });

  test('recovery store atomically replaces the previous snapshot', () async {
    final directory = await Directory.systemTemp.createTemp('revv-recovery');
    addTearDown(() => directory.delete(recursive: true));
    final store = RunRecoveryStore(directoryProvider: () async => directory);

    await store.writeSnapshot(_snapshot(distanceKm: 1.0));
    await store.writeSnapshot(_snapshot(distanceKm: 2.0));

    expect((await store.readSnapshot())?.distanceKm, 2.0);
    expect(
      File('${directory.path}/run_recovery.json.tmp').existsSync(),
      isFalse,
    );
  });

  testWidgets('valid recovery can be saved and cleared', (tester) async {
    final store = _FakeRecoveryStore(snapshot: _snapshot(distanceKm: 1.2));
    final history = _CountingHistory();
    await _pumpShell(tester, store: store, history: history);

    expect(
      find.text('A previous drive is still available. Save it?'),
      findsOneWidget,
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(history.saveCount, 1);
    expect(store.clearCount, 1);
    final detail = await history.loadDetail(history.history.single.id);
    expect(detail?.routeSnapshot?['nodes'], hasLength(10));
    expect(detail?.samples.single.lat, 45.001);
    expect(detail?.sharpEvents, hasLength(1));
  });

  testWidgets('failed recovery retains the snapshot and retries full save', (
    tester,
  ) async {
    final store = _FakeRecoveryStore(snapshot: _snapshot(distanceKm: 1.2));
    final history = _CountingHistory()..failures = 1;
    await _pumpShell(tester, store: store, history: history);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(store.clearCount, 0);
    expect(store.snapshot, isNotNull);
    expect(find.text('Retry save'), findsOneWidget);
    await tester.tap(find.text('Retry save'));
    await tester.pumpAndSettle();
    expect(store.clearCount, 1);
    expect(history.history, hasLength(1));
    expect(
      (await history.loadDetail(
        history.history.single.id,
      ))?.routeSnapshot?['nodes'],
      hasLength(10),
    );
  });

  test(
    'stopping before 30 seconds persists the final recovery sample',
    () async {
      var now = DateTime.utc(2026, 9, 8);
      final store = _FakeRecoveryStore();
      final service = RunSessionService(clock: () => now, recoveryStore: store);
      service.startSession(_route);
      await _flushAsync();
      now = now.add(const Duration(seconds: 2));
      service.recordPosition(45, -73, 30);
      final stopped = service.stopSession();
      await _flushAsync();
      expect(store.snapshot?.toRunSession().runId, stopped?.runId);
      expect(store.snapshot?.gpsPath, hasLength(1));
      expect(store.snapshot?.lastSampleTime, now);
      expect(store.snapshot?.telemetrySamples, hasLength(1));
    },
  );

  testWidgets('valid recovery can be discarded without saving', (tester) async {
    final store = _FakeRecoveryStore(snapshot: _snapshot(distanceKm: 1.2));
    final history = _CountingHistory();
    await _pumpShell(tester, store: store, history: history);

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(history.saveCount, 0);
    expect(store.clearCount, 1);
  });

  testWidgets('short recovery clears without a dialog', (tester) async {
    final store = _FakeRecoveryStore(snapshot: _snapshot(distanceKm: 0.4));
    final history = _CountingHistory();
    await _pumpShell(tester, store: store, history: history);
    await tester.pumpAndSettle();

    expect(
      find.text('A previous drive is still available. Save it?'),
      findsNothing,
    );
    expect(history.saveCount, 0);
    expect(store.clearCount, 1);
  });

  testWidgets('recovery is resolved before the pending drive prompt', (
    tester,
  ) async {
    final store = _FakeRecoveryStore(snapshot: _snapshot(distanceKm: 1.2));
    final history = _CountingHistory();
    final routes = RouteService()
      ..pendingGuideRoute = _route
      ..pendingGuideStartedAt = DateTime.now();
    await _pumpShell(
      tester,
      store: store,
      history: history,
      routeService: routes,
    );

    expect(
      find.text('A previous drive is still available. Save it?'),
      findsOneWidget,
    );
    expect(find.text('Route reached. Start the drive?'), findsNothing);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(find.text('Route reached. Start the drive?'), findsOneWidget);
  });
}

Future<void> _pumpShell(
  WidgetTester tester, {
  required _FakeRecoveryStore store,
  required _CountingHistory history,
  RouteService? routeService,
}) async {
  SharedPreferences.setMockInitialValues({});
  await tester.binding.setSurfaceSize(const Size(430, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<RunHistoryService>.value(value: history),
        ChangeNotifierProvider(
          create: (_) => DrivenRoutesService(history: history),
        ),
        ChangeNotifierProvider(create: (_) => SettingsService()),
        ChangeNotifierProvider<LocationService>.value(value: _FakeLocation()),
        ChangeNotifierProvider(create: (_) => WeatherService()),
        ChangeNotifierProvider.value(value: routeService ?? RouteService()),
        ChangeNotifierProvider(create: (_) => RunSessionService()),
        ChangeNotifierProvider.value(value: SupabaseService()),
      ],
      child: MaterialApp(home: LeanAppShellScreen(recoveryStore: store)),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _flushAsync() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

RunRecoverySnapshot _snapshot({required double distanceKm}) {
  final start = DateTime.parse('2026-07-11T10:00:00Z');
  return RunRecoverySnapshot(
    startTime: start,
    routeId: 'route',
    routeName: 'Recovery Route',
    gpsPath: List.generate(10, (index) => LatLng(45 + index * 0.001, -73)),
    distanceKm: distanceKm,
    maxSpeedKmh: 70,
    totalSpeedSum: 90,
    speedSamples: 2,
    driveModeSeconds: const {'cruise': 20, 'winding': 10},
    sharpCorners: [
      SharpCorner(
        position: const LatLng(45.005, -73),
        lateralG: 0.5,
        time: start.add(const Duration(seconds: 20)),
      ),
    ],
    telemetrySamples: const [
      TelemetrySample(
        tMs: 1000,
        lat: 45.001,
        lng: -73,
        speedKmh: 40,
        lateralG: 0.2,
        longitudinalG: 0.1,
        driveMode: 'cruise',
      ),
    ],
    weatherEmoji: '🌤',
    tempDisplay: '20°C',
    weatherDesc: 'Clear',
    lastSampleTime: start.add(const Duration(seconds: 30)),
  );
}

class _FakeRecoveryStore extends RunRecoveryStore {
  _FakeRecoveryStore({this.snapshot, this.writeFailures = 0});

  RunRecoverySnapshot? snapshot;
  int writeFailures;
  int writeCount = 0;
  int clearCount = 0;

  @override
  Future<void> writeSnapshot(RunRecoverySnapshot snapshot) async {
    writeCount++;
    if (writeFailures > 0) {
      writeFailures--;
      throw const FileSystemException('write failed');
    }
    this.snapshot = snapshot;
  }

  @override
  Future<RunRecoverySnapshot?> readSnapshot() async => snapshot;

  @override
  Future<void> clear({String? runId}) async {
    clearCount++;
    snapshot = null;
  }
}

class _CountingHistory extends RunHistoryService {
  int saveCount = 0;
  int failures = 0;

  @override
  Future<RunSummary> saveSession(RunSession session) async {
    saveCount++;
    if (failures-- > 0) throw StateError("disk unavailable");
    return super.saveSession(session);
  }
}

class _FakeLocation extends LocationService {
  @override
  bool get hasBestKnownLocation => true;

  @override
  LatLng? get bestKnownLatLng => const LatLng(45, -73);

  @override
  Future<void> requestPermission() async {}

  @override
  Future<void> startTracking() async {}

  @override
  Future<LatLng?> ensureLiveLocation({
    Duration timeout = const Duration(seconds: 6),
  }) async => bestKnownLatLng;
}

const _route = RevvRoute(
  id: 'route',
  name: 'Route',
  nodes: [LatLng(45, -73), LatLng(45.01, -73.01)],
  distanceKm: 2,
  distanceFromUser: 0,
  windingScore: 1,
  starRating: 1,
  sharpCurveCount: 1,
  centerPoint: LatLng(45, -73),
);

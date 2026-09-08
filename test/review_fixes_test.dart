import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/core/storage_keys.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/models/route_feedback.dart';
import 'package:revv_app/models/run_session.dart';
import 'package:revv_app/models/run_summary.dart';
import 'package:revv_app/models/run_telemetry_detail.dart';
import 'package:revv_app/services/drive_dynamics_tracker.dart';
import 'package:revv_app/services/run_history_service.dart';
import 'package:revv_app/services/run_local_store.dart';
import 'package:revv_app/services/run_pending_upload_store.dart';
import 'package:revv_app/services/secure_session_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:geolocator/geolocator.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:revv_app/services/location_service.dart';
import 'package:revv_app/services/run_session_service.dart';
import 'package:revv_app/services/run_recovery_store.dart';
import 'package:revv_app/services/route_auto_record_service.dart';
import 'package:revv_app/services/route_service.dart';

// Regression coverage for the September 8 review fixes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('local detail opens without querying a stalled cloud', () async {
    final cloud = _SlowDetailCloud();
    final local = PreferencesRunLocalStore();
    final history = RunHistoryService(
      cloudClient: cloud,
      localStore: local,
      pendingStore: _pendingStore(),
    );
    final saved = await history.saveSession(_sessionWithRoute());
    expect(await local.loadDetail(saved.id), isNotNull);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(StorageKeys.cloudRunStorageEnabled, true);
    var done = false;
    final opening = history.loadDetail(saved.id).then((d) {
      done = true;
      return d;
    });
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(cloud.fetches, 0);
    expect(done, true);
    cloud.remote.complete(null);
    expect(await opening, isNotNull);
  });

  test('unchanged detail is uploaded once, including after restart', () async {
    final cloud = _FakeCloud();
    final history = RunHistoryService(
      cloudClient: cloud,
      pendingStore: _pendingStore(),
    );
    await history.saveSession(_sessionWithRoute());
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(StorageKeys.cloudRunStorageEnabled, true);
    expect(await history.syncWithCloud(), true);
    expect(cloud.uploadDetailCount, 1);
    expect(await history.syncWithCloud(), true);
    expect(cloud.uploadDetailCount, 1);
    final reloaded = RunHistoryService(
      cloudClient: cloud,
      pendingStore: _pendingStore(),
    );
    await reloaded.load();
    await reloaded.syncWithCloud();
    expect(cloud.uploadDetailCount, 1);
    await reloaded.syncWithCloud(repairDetails: true);
    expect(cloud.uploadDetailCount, 2);
  });

  test(
    'completed auto-save preserves the next active recovery snapshot',
    () async {
      var now = DateTime.utc(2026, 9, 8);
      final store = _MemoryRecovery();
      final sessions = RunSessionService(
        clock: () => now,
        recoveryStore: store,
      );
      final route = _sessionWithRoute().route!;
      final routes = RouteService()..beginGuideToStart(route);
      final save = Completer<void>();
      final finished = Completer<void>();
      final auto = RouteAutoRecordService(
        routes: routes,
        sessions: sessions,
        maxUnclaimedDuration: const Duration(seconds: 10),
        onCompleted: (completed) async {
          await save
              .future; // Same ordering as main.dart's onCompleted callback.
          await sessions.clearRecovery(runId: completed.runId);
          finished.complete();
        },
      );
      for (final seconds in [0, 6, 17]) {
        now = DateTime.utc(2026, 9, 8).add(Duration(seconds: seconds));
        auto.handleFix(
          AutoRecordFix(
            point: route.nodes.first,
            speedKmh: 20,
            accuracyM: 5,
            timestamp: now,
          ),
        );
      }
      expect(auto.state, AutoRecordState.idle);
      expect(save.isCompleted, false);
      sessions.startSession(route);
      now = now.add(const Duration(seconds: 31));
      sessions.recordPosition(45, -73, 20);
      await Future<void>.delayed(Duration.zero);
      expect(store.snapshot, isNotNull);
      expect(sessions.isRecording, true);
      save.complete();
      await finished.future;
      expect(sessions.isRecording, true);
      expect(store.snapshot, isNotNull);
      sessions.stopSession();
      auto.dispose();
      routes.dispose();
      sessions.dispose();
    },
  );

  test(
    'GPS wait uses one total deadline with no competing subscription',
    () async {
      final original = GeolocatorPlatform.instance;
      final platform = _NoFixPlatform();
      GeolocatorPlatform.instance = platform;
      final location = LocationService()
        ..hasPermission = true
        ..isTracking = true;
      final clock = Stopwatch()..start();
      final result = await location.ensureLiveLocation(
        timeout: const Duration(milliseconds: 80),
      );
      clock.stop();
      expect(result, isNull);
      expect(platform.singleRequests, 0);
      expect(clock.elapsedMilliseconds, lessThan(200));
      location.dispose();
      GeolocatorPlatform.instance = original;
      await platform.stream.close();
    },
  );

  test(
    'database initialization is retried after transient open failure',
    () async {
      sqfliteFfiInit();
      final directory = await Directory.systemTemp.createTemp(
        'revv-open-retry',
      );
      addTearDown(() => directory.delete(recursive: true));
      var attempts = 0;
      final local = SqfliteRunLocalStore(
        factory: databaseFactoryFfi,
        databasePath: () async {
          attempts++;
          if (attempts == 1) {
            throw StateError('transient database path failure');
          }
          return '${directory.path}/runs.db';
        },
      );
      await expectLater(local.loadRuns(), throwsStateError);
      expect(await local.loadRuns(), isEmpty);
      expect(attempts, 2);
      await local.close();
    },
  );
  test(
    'two unsaved drives remain on disk and scoped clearing preserves the other',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'revv-scoped-recovery',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = RunRecoveryStore(directoryProvider: () async => directory);
      var now = DateTime.utc(2026, 9, 8);
      final sessions = RunSessionService(
        clock: () => now,
        recoveryStore: store,
      );
      sessions.startSession(_sessionWithRoute().route);
      sessions.recordPosition(45, -73, 30);
      final first = sessions.stopSession()!;
      now = now.add(const Duration(minutes: 1));
      sessions.startSession(_sessionWithRoute().route);
      sessions.recordPosition(45.001, -73, 30);
      final second = sessions.stopSession()!;
      // A no-op scoped clear also joins all queued snapshot writes.
      await sessions.clearRecovery(runId: 'not-a-run');
      expect((await store.readSnapshot())?.recoveryId, first.runId);
      await sessions.clearRecovery(runId: first.runId);
      final remaining = await store.readSnapshot();
      expect(remaining?.recoveryId, second.runId);
      expect(
        remaining?.toRunSession().route?.distanceKm,
        second.route?.distanceKm,
      );
      await sessions.clearRecovery(runId: second.runId);
      expect(await store.readSnapshot(), isNull);
      sessions.dispose();
    },
  );

  test(
    'changed detail is retried until upload succeeds and then stays clean',
    () async {
      final cloud = _FakeCloud();
      final history = RunHistoryService(
        cloudClient: cloud,
        pendingStore: _pendingStore(),
      );
      final summary = await history.saveSession(_sessionWithRoute());
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(StorageKeys.cloudRunStorageEnabled, true);
      await history.syncWithCloud();
      final original = await history.loadDetail(summary.id);
      final changed = RunTelemetryDetail.fromJson({
        ...original!.toJson(),
        'weather': {'description': 'changed'},
      });
      cloud.uploadDetailResult = false;
      await history.saveDetail(changed);
      expect(cloud.uploadDetailCount, 2);
      cloud.uploadDetailResult = true;
      await history.retryPendingUploads();
      expect(cloud.uploadDetailCount, 3);
      await history.syncWithCloud();
      expect(cloud.uploadDetailCount, 3);
    },
  );
  testWidgets(
    'data deletion waits for an in-flight detail upload to actually finish',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        StorageKeys.cloudRunStorageEnabled: true,
      });
      final upload = Completer<bool>();
      final cloud = _FakeCloud()..detailCompletion = upload;
      final history = RunHistoryService(
        cloudClient: cloud,
        pendingStore: _pendingStore(),
      );
      await history.saveSession(_sessionWithRoute());
      await tester.pump();
      expect(cloud.uploadDetailCount, 1);
      final deletion = history.deleteAllRunData();
      await tester.pump(const Duration(seconds: 20));
      expect(cloud.deleteCount, 0);
      upload.complete(true);
      await tester.pump();
      await deletion;
      expect(cloud.deleteCount, 1);
      expect(history.history, isEmpty);
    },
  );
}

class _SlowDetailCloud extends _FakeCloud {
  final remote = Completer<RunTelemetryDetail?>();
  int fetches = 0;
  @override
  Future<RunTelemetryDetail?> fetchRunDetail(String id) {
    fetches++;
    return remote.future;
  }
}

class _MemoryRecovery extends RunRecoveryStore {
  RunRecoverySnapshot? snapshot;
  @override
  Future<void> clear({String? runId}) async {
    if (runId == null || snapshot?.toRunSession().runId == runId) {
      snapshot = null;
    }
  }

  @override
  Future<void> writeSnapshot(RunRecoverySnapshot value) async {
    snapshot = value;
  }

  @override
  Future<RunRecoverySnapshot?> readSnapshot() async => snapshot;
}

class _NoFixPlatform extends GeolocatorPlatform {
  final stream = StreamController<Position>.broadcast();
  int singleRequests = 0;
  @override
  Future<Position?> getLastKnownPosition({
    bool forceLocationManager = false,
  }) async => null;
  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) =>
      stream.stream;
  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    singleRequests++;
    await Future<void>.delayed(locationSettings!.timeLimit!);
    throw TimeoutException('no fix');
  }
}

RunPendingUploadStore _pendingStore() =>
    RunPendingUploadStore(detailStore: MemorySecureStringStore());

RunSession _sessionWithRoute({RevvRoute? route}) {
  final start = DateTime.parse('2026-05-08T00:00:00Z');
  return RunSession(
    startTime: start,
    endTime: start.add(const Duration(minutes: 3)),
    maxSpeedKmh: 50,
    avgSpeedKmh: 35,
    distanceKm: 2.1,
    gpsPath: const [LatLng(45, -73), LatLng(45.01, -73.01)],
    route:
        route ??
        const RevvRoute(
          id: 'route-1',
          name: 'Test Route',
          nodes: [LatLng(45, -73), LatLng(45.01, -73.01)],
          distanceKm: 2.1,
          windingScore: 4,
          starRating: 4,
          sharpCurveCount: 2,
          centerPoint: LatLng(45, -73),
          distanceFromUser: 0.5,
        ),
    weatherEmoji: '',
    tempDisplay: '',
    weatherDesc: '',
  );
}

class _FakeCloud implements RunHistoryCloudClient {
  bool uploadDetailResult = true;
  Completer<bool>? detailCompletion;
  int deleteCount = 0;
  var uploadDetailCount = 0;
  final remoteRunIds = <String>{};
  @override
  bool get isReady => true;
  @override
  String? get uid => 'user-1';
  @override
  Future<bool> deleteUserRunData() async {
    deleteCount++;
    return true;
  }

  @override
  Future<RunTelemetryDetail?> fetchRunDetail(String runId) async => null;
  @override
  Future<List<RunSummary>> fetchMissingRuns(Set<String> localIds) async =>
      const [];
  @override
  Future<Set<String>?> fetchRunIds() async => Set.of(remoteRunIds);
  @override
  Future<bool> recordRouteRun(String? routeId, String runId) async => true;
  @override
  Future<bool> uploadRouteFeedback(RouteFeedback feedback) async => true;
  @override
  Future<bool> uploadRun(RunSummary summary) async {
    remoteRunIds.add(summary.id);
    return true;
  }

  @override
  Future<bool> uploadRunDetail(RunTelemetryDetail detail) async {
    uploadDetailCount++;
    return detailCompletion?.future ?? uploadDetailResult;
  }

  @override
  Future<bool> uploadTelemetrySummary(
    String runId,
    DriveDynamicsSummary summary,
  ) async => true;
}

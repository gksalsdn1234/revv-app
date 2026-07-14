import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/core/storage_keys.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/models/route_feedback.dart';
import 'package:revv_app/models/run_session.dart';
import 'package:revv_app/models/run_summary.dart';
import 'package:revv_app/models/run_telemetry_detail.dart';
import 'package:revv_app/services/drive_dynamics_tracker.dart';
import 'package:revv_app/services/run_history_service.dart';
import 'package:revv_app/services/run_pending_upload_store.dart';
import 'package:revv_app/services/secure_session_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('RunPendingUploadStore keeps detail until explicitly removed', () async {
    SharedPreferences.setMockInitialValues({});
    final store = _pendingStore();
    final detail = _detail('run-1');

    await store.saveDetail(detail);
    expect((await store.loadDetail('run-1'))?.runId, 'run-1');
    expect(await store.hasPending(), isTrue);

    await store.removeDetail('run-1');
    expect(await store.loadDetail('run-1'), isNull);
    expect(await store.hasPending(), isFalse);
  });

  test('RunPendingUploadStore does not delete local rich detail', () async {
    SharedPreferences.setMockInitialValues({});
    final store = _pendingStore();
    final prefs = await SharedPreferences.getInstance();
    final detail = _detail('run-1');
    await prefs.setString(
      '${StorageKeys.runDetailPrefix}run-1',
      jsonEncode(detail.toJson()),
    );

    await store.saveDetail(detail);
    await store.removeDetail('run-1');

    expect(prefs.getString('${StorageKeys.runDetailPrefix}run-1'), isNotNull);

    await store.saveDetail(detail);
    await store.clearAll();

    expect(prefs.getString('${StorageKeys.runDetailPrefix}run-1'), isNotNull);
  });

  test(
    'RunHistoryService removes pending detail after cloud upload success',
    () async {
      SharedPreferences.setMockInitialValues({
        StorageKeys.cloudRunStorageEnabled: true,
      });
      final pending = _pendingStore();
      final history = RunHistoryService(
        pendingStore: pending,
        cloudClient: _FakeCloud(uploadDetailResult: true),
      );

      await history.saveDetail(_detail('run-1'));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(StorageKeys.pendingRunDetailsIndex), isNull);
      expect(prefs.getString('${StorageKeys.runDetailPrefix}run-1'), isNotNull);
    },
  );

  test(
    'RunHistoryService keeps pending detail after cloud upload failure',
    () async {
      SharedPreferences.setMockInitialValues({
        StorageKeys.cloudRunStorageEnabled: true,
      });
      final pending = _pendingStore();
      final cloud = _FakeCloud(uploadDetailResult: false);
      final history = RunHistoryService(
        pendingStore: pending,
        cloudClient: cloud,
      );

      await history.saveDetail(_detail('run-1'));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('${StorageKeys.runDetailPrefix}run-1'), isNotNull);
      expect((await pending.loadDetail('run-1'))?.runId, 'run-1');
      expect(cloud.uploadDetailCount, 1);
    },
  );

  test(
    'RunHistoryService saves local detail when cloud storage is off',
    () async {
      SharedPreferences.setMockInitialValues({
        StorageKeys.cloudRunStorageEnabled: false,
      });
      final pending = _pendingStore();
      final cloud = _FakeCloud(uploadDetailResult: true);
      final history = RunHistoryService(
        pendingStore: pending,
        cloudClient: cloud,
      );

      await history.saveDetail(_detail('run-1'));

      expect(cloud.uploadDetailCount, 0);
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('${StorageKeys.runDetailPrefix}run-1');
      expect(raw, isNotNull);
      expect(
        RunTelemetryDetail.fromJson(
          jsonDecode(raw!) as Map<String, dynamic>,
        ).runId,
        'run-1',
      );
      expect(prefs.getString(StorageKeys.pendingRunDetailsIndex), isNull);
      expect((await history.loadDetail('run-1'))?.runId, 'run-1');
      expect(prefs.getString('${StorageKeys.runDetailPrefix}run-1'), isNotNull);
    },
  );

  test(
    'RunHistoryService defaults fresh install detail upload to local only',
    () async {
      SharedPreferences.setMockInitialValues({});
      final pending = _pendingStore();
      final cloud = _FakeCloud(uploadDetailResult: true);
      final history = RunHistoryService(
        pendingStore: pending,
        cloudClient: cloud,
      );

      await history.saveDetail(_detail('fresh-run'));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(StorageKeys.cloudRunStorageEnabled), isFalse);
      expect(cloud.uploadDetailCount, 0);
      expect(
        prefs.getString('${StorageKeys.runDetailPrefix}fresh-run'),
        isNotNull,
      );
      expect(prefs.getString(StorageKeys.pendingRunDetailsIndex), isNull);
    },
  );

  test(
    'RunHistoryService does not record route usage when cloud storage is off',
    () async {
      SharedPreferences.setMockInitialValues({
        StorageKeys.cloudRunStorageEnabled: false,
      });
      final cloud = _FakeCloud();
      final history = RunHistoryService(cloudClient: cloud);

      await history.save(_sessionWithRoute());

      expect(cloud.recordedRouteIds, isEmpty);
    },
  );

  test(
    'route usage receipt retries after its parent run upload succeeds',
    () async {
      SharedPreferences.setMockInitialValues({
        StorageKeys.cloudRunStorageEnabled: true,
      });
      final cloud = _RetryRunCloud();
      final history = RunHistoryService(cloudClient: cloud);

      await history.save(_sessionWithRoute());
      await cloud.firstAttempted.future;
      expect(cloud.recordedRouteIds, isEmpty);

      await history.retryPendingUploads();

      expect(cloud.recordedRouteIds, ['route-1']);
    },
  );

  test(
    'composite chain uploads history without crediting one source route',
    () async {
      SharedPreferences.setMockInitialValues({
        StorageKeys.cloudRunStorageEnabled: true,
      });
      final cloud = _FakeCloud();
      final history = RunHistoryService(cloudClient: cloud);
      final session = _sessionWithRoute(
        route: const RevvRoute(
          id: 'chain:first/second',
          name: 'Route chain · 2',
          nodes: [LatLng(45, -73), LatLng(45.02, -73.02)],
          distanceKm: 4.2,
          windingScore: 5,
          starRating: 4,
          sharpCurveCount: 4,
          centerPoint: LatLng(45.01, -73.01),
          distanceFromUser: 0,
        ),
      );

      final summary = await history.save(session);
      await Future<void>.delayed(Duration.zero);

      expect(summary.routeId, 'chain:first/second');
      expect(cloud.recordedRouteIds, isEmpty);
    },
  );

  test('RunHistoryService ignores telemetry summary upload failure', () async {
    SharedPreferences.setMockInitialValues({
      StorageKeys.cloudRunStorageEnabled: true,
    });
    final cloud = _FakeCloud(uploadTelemetrySummaryResult: false);
    final history = RunHistoryService(cloudClient: cloud);

    final summary = await history.save(_sessionWithRoute());
    await Future<void>.delayed(Duration.zero);

    expect(summary.id, isNotEmpty);
    expect(history.history, hasLength(1));
    expect(cloud.uploadTelemetrySummaryCount, 1);
    expect(cloud.lastTelemetrySummary?.hardBrakeCount, 0);
  });

  test(
    'deleteAllRunData clears local data and queues failed cloud delete',
    () async {
      SharedPreferences.setMockInitialValues({
        StorageKeys.cloudRunStorageEnabled: true,
      });
      final cloud = _FakeCloud(deleteResult: false);
      final history = RunHistoryService(cloudClient: cloud);
      await history.load();
      await history.save(_sessionWithRoute());

      final deleted = await history.deleteAllRunData();

      expect(deleted, isFalse);
      expect(history.history, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getStringList(StorageKeys.pendingRunDataDeletionUids),
        contains('user-1'),
      );
    },
  );

  test(
    'deleteAllRunData removes rich local detail after cloud delete succeeds',
    () async {
      SharedPreferences.setMockInitialValues({
        StorageKeys.cloudRunStorageEnabled: true,
      });
      final pending = _pendingStore();
      final history = RunHistoryService(
        pendingStore: pending,
        cloudClient: _FakeCloud(deleteResult: true),
      );
      await history.load();
      final summary = await history.save(_sessionWithRoute());
      await history.saveDetail(_detail(summary.id));

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('${StorageKeys.runDetailPrefix}${summary.id}'),
        isNotNull,
      );

      final deleted = await history.deleteAllRunData();

      expect(deleted, isTrue);
      expect(history.history, isEmpty);
      expect(
        prefs.getString('${StorageKeys.runDetailPrefix}${summary.id}'),
        isNull,
      );
      expect(await pending.hasPending(), isFalse);
    },
  );

  test('delete waits for an in-flight upload and runs last', () async {
    SharedPreferences.setMockInitialValues({
      StorageKeys.cloudRunStorageEnabled: true,
    });
    final upload = Completer<bool>();
    final cloud = _FakeCloud(uploadRunCompleter: upload);
    final history = RunHistoryService(cloudClient: cloud);
    await history.load();
    await history.save(_sessionWithRoute());
    await Future<void>.delayed(Duration.zero);

    final deletion = history.deleteAllRunData();
    await Future<void>.delayed(Duration.zero);
    expect(cloud.deleteCount, 0);

    upload.complete(true);
    expect(await deletion, isTrue);
    expect(cloud.events, ['upload', 'delete']);
  });

  test('delete waits for an in-flight sync and runs last', () async {
    SharedPreferences.setMockInitialValues({
      StorageKeys.cloudRunStorageEnabled: true,
    });
    final fetch = Completer<List<RunSummary>>();
    final cloud = _FakeCloud(fetchMissingCompleter: fetch);
    final history = RunHistoryService(cloudClient: cloud);
    await history.load();

    final sync = history.syncWithCloud();
    await Future<void>.delayed(Duration.zero);
    final deletion = history.deleteAllRunData();
    await Future<void>.delayed(Duration.zero);
    expect(cloud.deleteCount, 0);

    fetch.complete(const []);
    await sync;
    expect(await deletion, isTrue);
    expect(cloud.events, ['fetch', 'delete']);
    expect(history.history, isEmpty);
  });

  test('pending deletion does not erase a replacement identity', () async {
    SharedPreferences.setMockInitialValues({
      StorageKeys.cloudRunStorageEnabled: true,
    });
    final cloud = _FakeCloud(deleteResult: false);
    final history = RunHistoryService(cloudClient: cloud);
    await history.load();
    cloud.deleteResult = false;
    await history.deleteAllRunData();

    cloud
      ..userId = 'user-2'
      ..deleteResult = true;
    await history.syncWithCloud();

    expect(cloud.deleteCount, 1);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getStringList(StorageKeys.pendingRunDataDeletionUids),
      contains('user-1'),
    );

    cloud.deleteResult = false;
    await history.deleteAllRunData();
    expect(
      prefs.getStringList(StorageKeys.pendingRunDataDeletionUids),
      containsAll(['user-1', 'user-2']),
    );
  });

  test('purgePendingUploads preserves local rich detail', () async {
    SharedPreferences.setMockInitialValues({
      StorageKeys.cloudRunStorageEnabled: true,
    });
    final pending = _pendingStore();
    final history = RunHistoryService(
      pendingStore: pending,
      cloudClient: _FakeCloud(uploadDetailResult: false),
    );
    final detail = _detail('run-1');

    await history.saveDetail(detail);
    await history.purgePendingUploads();

    expect(await pending.hasPending(), isFalse);
    expect((await history.loadDetail('run-1'))?.runId, 'run-1');
  });

  test(
    'RunPendingUploadStore migrates legacy detail map to secure store',
    () async {
      final detail = _detail('legacy-run');
      SharedPreferences.setMockInitialValues({
        StorageKeys.pendingRunDetails: jsonEncode({
          'legacy-run': detail.toJson(),
        }),
      });
      final secure = MemorySecureStringStore();
      final store = RunPendingUploadStore(detailStore: secure);

      expect((await store.loadDetail('legacy-run'))?.runId, 'legacy-run');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(StorageKeys.pendingRunDetails), isNull);
      expect(
        await secure.read(
          '${StorageKeys.pendingRunDetailSecurePrefix}legacy-run',
        ),
        isNotNull,
      );
    },
  );

  test('RunPendingUploadStore clears corrupt secure detail payload', () async {
    SharedPreferences.setMockInitialValues({
      StorageKeys.pendingRunDetailsIndex: jsonEncode(['broken-run']),
    });
    final secure = MemorySecureStringStore();
    await secure.write(
      '${StorageKeys.pendingRunDetailSecurePrefix}broken-run',
      '{not-json',
    );
    final store = RunPendingUploadStore(detailStore: secure);

    expect(await store.loadDetail('broken-run'), isNull);
    expect(
      await secure.read(
        '${StorageKeys.pendingRunDetailSecurePrefix}broken-run',
      ),
      isNull,
    );
    expect(await store.hasPending(), isFalse);
  });

  test('RunPendingUploadStore purges stale detail payloads by TTL', () async {
    SharedPreferences.setMockInitialValues({});
    final store = _pendingStore();
    final now = DateTime.now().toUtc();
    await store.saveDetail(
      _detail('old-run', createdAt: now.subtract(const Duration(days: 15))),
    );
    await store.saveDetail(
      _detail('fresh-run', createdAt: now.subtract(const Duration(days: 7))),
    );

    final removed = await store.purgeStaleDetails(
      now: now,
      maxAge: const Duration(days: 14),
    );

    expect(removed, 1);
    expect(await store.loadDetail('old-run'), isNull);
    expect((await store.loadDetail('fresh-run'))?.runId, 'fresh-run');
    expect(await store.hasPending(), isTrue);
  });
}

RunPendingUploadStore _pendingStore() =>
    RunPendingUploadStore(detailStore: MemorySecureStringStore());

RunTelemetryDetail _detail(String runId, {DateTime? createdAt}) =>
    RunTelemetryDetail(
      runId: runId,
      version: 1,
      routeSnapshot: const {'id': 'route-1'},
      samples: const [
        TelemetrySample(
          tMs: 0,
          lat: 45,
          lng: -73,
          speedKmh: 42,
          lateralG: 0.1,
          longitudinalG: 0.02,
          driveMode: 'cruise',
        ),
      ],
      sharpEvents: const [],
      driveModeSeconds: const {'cruise': 1},
      weather: const {},
      createdAt: createdAt ?? DateTime.now().toUtc(),
    );

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
  _FakeCloud({
    this.uploadDetailResult = true,
    this.deleteResult = true,
    this.uploadTelemetrySummaryResult = true,
    this.uploadRunCompleter,
    this.fetchMissingCompleter,
  });

  final bool uploadDetailResult;
  bool deleteResult;
  final bool uploadTelemetrySummaryResult;
  final Completer<bool>? uploadRunCompleter;
  final Completer<List<RunSummary>>? fetchMissingCompleter;
  String userId = 'user-1';
  final recordedRouteIds = <String?>[];
  final events = <String>[];
  var uploadDetailCount = 0;
  var uploadTelemetrySummaryCount = 0;
  var deleteCount = 0;
  DriveDynamicsSummary? lastTelemetrySummary;

  @override
  bool get isReady => true;

  @override
  String? get uid => userId;

  @override
  Future<bool> deleteUserRunData() async {
    deleteCount++;
    events.add('delete');
    return deleteResult;
  }

  @override
  Future<RunTelemetryDetail?> fetchRunDetail(String runId) async => null;

  @override
  Future<List<RunSummary>> fetchMissingRuns(Set<String> localIds) async {
    events.add('fetch');
    return fetchMissingCompleter?.future ?? const [];
  }

  @override
  Future<Set<String>> fetchRunIds() async => {};

  @override
  Future<void> recordRouteRun(String? routeId, String runId) async {
    recordedRouteIds.add(routeId);
  }

  @override
  Future<bool> uploadRouteFeedback(RouteFeedback feedback) async => true;

  @override
  Future<bool> uploadRun(RunSummary summary) async {
    events.add('upload');
    return uploadRunCompleter?.future ?? true;
  }

  @override
  Future<bool> uploadRunDetail(RunTelemetryDetail detail) async {
    uploadDetailCount++;
    return uploadDetailResult;
  }

  @override
  Future<bool> uploadTelemetrySummary(
    String runId,
    DriveDynamicsSummary summary,
  ) async {
    uploadTelemetrySummaryCount++;
    lastTelemetrySummary = summary;
    return uploadTelemetrySummaryResult;
  }
}

class _RetryRunCloud extends _FakeCloud {
  final firstAttempted = Completer<void>();
  var attempts = 0;

  @override
  Future<bool> uploadRun(RunSummary summary) async {
    attempts++;
    if (attempts == 1) firstAttempted.complete();
    return attempts > 1;
  }
}

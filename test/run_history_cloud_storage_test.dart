import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/core/storage_keys.dart';
import 'package:revv_app/models/route_feedback.dart';
import 'package:revv_app/models/run_summary.dart';
import 'package:revv_app/models/run_telemetry_detail.dart';
import 'package:revv_app/services/run_history_service.dart';
import 'package:revv_app/services/run_pending_upload_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('RunPendingUploadStore keeps detail until explicitly removed', () async {
    SharedPreferences.setMockInitialValues({});
    const store = RunPendingUploadStore();
    final detail = _detail('run-1');

    await store.saveDetail(detail);
    expect((await store.loadDetail('run-1'))?.runId, 'run-1');
    expect(await store.hasPending(), isTrue);

    await store.removeDetail('run-1');
    expect(await store.loadDetail('run-1'), isNull);
    expect(await store.hasPending(), isFalse);
  });

  test(
    'RunHistoryService removes pending detail after cloud upload success',
    () async {
      SharedPreferences.setMockInitialValues({});
      const pending = RunPendingUploadStore();
      final history = RunHistoryService(
        pendingStore: pending,
        cloudClient: _FakeCloud(uploadDetailResult: true),
      );

      await history.saveDetail(_detail('run-1'));

      expect(await pending.loadDetail('run-1'), isNull);
      expect(await pending.hasPending(), isFalse);
    },
  );

  test(
    'RunHistoryService keeps pending detail after cloud upload failure',
    () async {
      SharedPreferences.setMockInitialValues({});
      const pending = RunPendingUploadStore();
      final history = RunHistoryService(
        pendingStore: pending,
        cloudClient: _FakeCloud(uploadDetailResult: false),
      );

      await history.saveDetail(_detail('run-1'));

      expect((await pending.loadDetail('run-1'))?.runId, 'run-1');
    },
  );

  test(
    'RunHistoryService does not persist detail when cloud storage is off',
    () async {
      SharedPreferences.setMockInitialValues({
        StorageKeys.cloudRunStorageEnabled: false,
      });
      const pending = RunPendingUploadStore();
      final history = RunHistoryService(
        pendingStore: pending,
        cloudClient: _FakeCloud(uploadDetailResult: true),
      );

      await history.saveDetail(_detail('run-1'));

      expect(await pending.loadDetail('run-1'), isNull);
    },
  );
}

RunTelemetryDetail _detail(String runId) => RunTelemetryDetail(
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
  obdSummary: null,
  weather: const {},
  createdAt: DateTime.parse('2026-05-08T00:00:00Z'),
);

class _FakeCloud implements RunHistoryCloudClient {
  _FakeCloud({this.uploadDetailResult = true});

  final bool uploadDetailResult;

  @override
  bool get isReady => true;

  @override
  Future<bool> deleteUserRunData() async => true;

  @override
  Future<RunTelemetryDetail?> fetchRunDetail(String runId) async => null;

  @override
  Future<List<RunSummary>> fetchMissingRuns(Set<String> localIds) async => [];

  @override
  Future<Set<String>> fetchRunIds() async => {};

  @override
  Future<void> recordRouteRun(String? routeId) async {}

  @override
  Future<bool> uploadRouteFeedback(RouteFeedback feedback) async => true;

  @override
  Future<bool> uploadRun(RunSummary summary) async => true;

  @override
  Future<bool> uploadRunDetail(RunTelemetryDetail detail) async =>
      uploadDetailResult;
}

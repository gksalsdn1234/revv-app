import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/core/storage_keys.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/models/route_feedback.dart';
import 'package:revv_app/models/run_summary.dart';
import 'package:revv_app/models/run_telemetry_detail.dart';
import 'package:revv_app/services/drive_dynamics_tracker.dart';
import 'package:revv_app/services/run_history_service.dart';
import 'package:revv_app/services/run_pending_upload_store.dart';
import 'package:revv_app/services/secure_session_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures/gps/replay_fixtures.dart';
import 'helpers/gps_replay.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('LTE shadow gap keeps replay session continuous', () {
    // Given: a Montreal-area GPS replay with a 5 minute sample gap.
    final replay = GpsReplayHarness();
    replay.start();

    // When: the trace is replayed without samples during the LTE shadow.
    replay.replay(montrealScenicReplay);
    final session = replay.stop();

    // Then: the session survives and distance does not contain a GPS jump.
    expect(
      session.duration.inSeconds,
      montrealScenicReplay.expectedDurationSeconds,
    );
    expect(
      session.distanceKm,
      closeTo(montrealScenicReplay.expectedDistanceKm, 0.000000001),
    );
    expect(session.gpsPath, hasLength(montrealScenicReplay.samples.length));
    expect(
      session.telemetrySamples[3].tMs - session.telemetrySamples[2].tMs,
      300000,
    );
    expect(_maxSegmentDistanceKm(session.gpsPath), lessThan(1.25));
    expect(
      replayFixtureDistanceKm(montrealScenicReplay),
      closeTo(10.40817871657922, 0.000000001),
    );
  });

  test('background pause and resume keeps recording continuity', () {
    // Given: an active replay session that has recorded the first corner leg.
    final replay = GpsReplayHarness();
    replay.start();
    replay.replay(montrealCornerReplay, endIndex: 4);

    // When: the sample stream pauses while backgrounded, then resumes.
    replay.advance(const Duration(seconds: 30));
    expect(replay.service.isRecording, isTrue);
    replay.replay(montrealCornerReplay, startIndex: 4);
    final session = replay.stop();

    // Then: path, duration, and sharp corner continuity are preserved.
    expect(session.gpsPath, hasLength(montrealCornerReplay.samples.length));
    expect(
      session.duration.inSeconds,
      montrealCornerReplay.expectedDurationSeconds,
    );
    expect(
      session.distanceKm,
      closeTo(montrealCornerReplay.expectedDistanceKm, 0.000000001),
    );
    expect(
      session.sharpCorners,
      hasLength(montrealCornerReplay.expectedSharpCornerCount),
    );
  });

  test(
    'offline detail upload failure queues replay and retry clears it',
    () async {
      // Given: cloud upload is enabled and the first detail upload fails.
      SharedPreferences.setMockInitialValues({
        StorageKeys.cloudRunStorageEnabled: true,
      });
      final pending = RunPendingUploadStore(
        detailStore: MemorySecureStringStore(),
      );
      final cloud = _RetryCloud(uploadDetailResults: [false, true]);
      final history = RunHistoryService(
        pendingStore: pending,
        cloudClient: cloud,
      );
      final replay = GpsReplayHarness();
      replay.start();
      replay.replay(montrealCornerReplay);
      final detail = RunTelemetryDetail.fromSession(
        'replay-run-1',
        replay.stop(),
      );

      // When: the detail is saved offline, then retry runs after reconnect.
      await history.saveDetail(detail);
      final queued = await pending.loadDetail('replay-run-1');
      await history.retryPendingUploads();

      // Then: the failed upload was queued and the retry emptied the queue.
      expect(queued?.runId, 'replay-run-1');
      expect(await pending.hasPending(), isFalse);
      expect(cloud.uploadDetailCount, 2);
    },
  );

  test(
    'completed replay saves summary distance duration and corner count',
    () async {
      // Given: a complete corner-event replay.
      SharedPreferences.setMockInitialValues({});
      final history = RunHistoryService(
        pendingStore: RunPendingUploadStore(
          detailStore: MemorySecureStringStore(),
        ),
        cloudClient: _RetryCloud(uploadDetailResults: const []),
      );
      final replay = GpsReplayHarness();
      replay.start();
      replay.replay(montrealCornerReplay);
      final session = replay.stop();

      // When: the replayed session is saved through RunHistoryService.
      final summary = await history.save(session);

      // Then: RunSummary matches the fixture expectations.
      expect(
        summary.distanceKm,
        closeTo(montrealCornerReplay.expectedDistanceKm, 0.000000001),
      );
      expect(
        summary.durationSeconds,
        montrealCornerReplay.expectedDurationSeconds,
      );
      expect(
        summary.sharpCornersCount,
        montrealCornerReplay.expectedSharpCornerCount,
      );
    },
  );
}

double _maxSegmentDistanceKm(List<LatLng> path) {
  var maxDistanceKm = 0.0;
  for (var i = 1; i < path.length; i++) {
    final distanceKm = RevvRoute.haversineKm(path[i - 1], path[i]);
    if (distanceKm > maxDistanceKm) maxDistanceKm = distanceKm;
  }
  return maxDistanceKm;
}

class _RetryCloud implements RunHistoryCloudClient {
  _RetryCloud({required List<bool> uploadDetailResults})
    : _uploadDetailResults = List.of(uploadDetailResults);

  final List<bool> _uploadDetailResults;
  var uploadDetailCount = 0;

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
  Future<bool> uploadRunDetail(RunTelemetryDetail detail) async {
    uploadDetailCount++;
    if (_uploadDetailResults.isEmpty) return true;
    return _uploadDetailResults.removeAt(0);
  }

  @override
  Future<bool> uploadTelemetrySummary(
    String runId,
    DriveDynamicsSummary summary,
  ) async => true;
}

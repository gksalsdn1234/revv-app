import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/core/storage_keys.dart';
import 'package:revv_app/models/route_feedback.dart';
import 'package:revv_app/models/run_summary.dart';
import 'package:revv_app/models/run_telemetry_detail.dart';
import 'package:revv_app/services/run_local_store.dart';
import 'package:revv_app/services/supabase_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'SQLite store migrates legacy JSON once and persists new data',
    () async {
      final run = _run('run-1');
      final feedback = _feedback('feedback-1', run.id);
      final detail = _detail(run.id);
      SharedPreferences.setMockInitialValues({
        StorageKeys.runs: RunSummary.listToJson([run]),
        StorageKeys.routeFeedback: RouteFeedback.listToJson([feedback]),
        '${StorageKeys.runDetailPrefix}${run.id}': jsonEncode(detail.toJson()),
      });
      final directory = await Directory.systemTemp.createTemp('revv-sqlite-');
      final databasePath = '${directory.path}/runs.db';
      final store = SqfliteRunLocalStore(
        factory: databaseFactoryFfi,
        databasePath: () async => databasePath,
      );

      expect((await store.loadRuns()).single.id, run.id);
      expect((await store.loadFeedback()).single.id, feedback.id);
      expect((await store.loadDetail(run.id))?.runId, run.id);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(StorageKeys.runs), isNull);
      expect(prefs.getString(StorageKeys.routeFeedback), isNull);
      expect(
        prefs.getString('${StorageKeys.runDetailPrefix}${run.id}'),
        isNull,
      );

      final second = _run('run-2');
      await store.saveRuns([second]);
      await store.close();
      final reopened = SqfliteRunLocalStore(
        factory: databaseFactoryFfi,
        databasePath: () async => databasePath,
      );
      addTearDown(() async {
        await reopened.close();
        await directory.delete(recursive: true);
      });

      expect((await reopened.loadRuns()).map((item) => item.id), [
        second.id,
        run.id,
      ]);
      expect((await reopened.loadDetail(run.id))?.runId, run.id);

      final replacement = RouteFeedback(
        id: 'feedback-2',
        runId: run.id,
        routeId: 'route-1',
        routeName: 'Test route',
        feedbackType: 'disliked',
        createdAt: DateTime.parse('2026-07-14T11:15:00Z'),
      );
      await reopened.saveFeedback(replacement);
      await reopened.close();
      final feedbackReopened = SqfliteRunLocalStore(
        factory: databaseFactoryFfi,
        databasePath: () async => databasePath,
      );
      addTearDown(feedbackReopened.close);
      final restoredFeedback = await feedbackReopened.loadFeedback();
      expect(restoredFeedback, hasLength(1));
      expect(restoredFeedback.single.id, replacement.id);
    },
  );

  test(
    'SQLite store does not expose runs after account owner changes',
    () async {
      SharedPreferences.setMockInitialValues({});
      final directory = await Directory.systemTemp.createTemp('revv-owner-');
      final databasePath = '${directory.path}/runs.db';
      final firstOwner = SqfliteRunLocalStore(
        factory: databaseFactoryFfi,
        databasePath: () async => databasePath,
        ownerUid: 'user-1',
      );
      await firstOwner.saveRunWithDetail(_run('run-1'), _detail('run-1'));
      await firstOwner.close();

      final secondOwner = SqfliteRunLocalStore(
        factory: databaseFactoryFfi,
        databasePath: () async => databasePath,
        ownerUid: 'user-2',
      );
      addTearDown(() async {
        await secondOwner.close();
        await directory.delete(recursive: true);
      });

      expect(await secondOwner.loadRuns(), isEmpty);
      expect(await secondOwner.loadDetail('run-1'), isNull);
    },
  );

  test('failed account deletion resume does not rebind SQLite owner', () async {
    SharedPreferences.setMockInitialValues({
      StorageKeys.pendingAccountDeletionUid: 'user-1',
    });
    final directory = await Directory.systemTemp.createTemp(
      'revv-pending-owner-',
    );
    final databasePath = '${directory.path}/runs.db';
    final supabase = SupabaseService()..debugResetForTesting();
    supabase.debugSetCloudSessionStateForTesting(
      ready: true,
      uid: 'user-1',
      anonymous: true,
    );
    final originalOwner = SqfliteRunLocalStore(
      factory: databaseFactoryFfi,
      databasePath: () async => databasePath,
      ownerUid: supabase.uid,
    );
    await originalOwner.saveRunWithDetail(_run('run-1'), _detail('run-1'));
    await originalOwner.close();

    supabase.debugSetCloudSessionStateForTesting(
      ready: false,
      uid: 'user-2',
      anonymous: true,
    );
    final unresolvedDeletion = SqfliteRunLocalStore(
      factory: databaseFactoryFfi,
      databasePath: () async => databasePath,
      ownerUid: supabase.uid,
    );
    addTearDown(() async {
      supabase.debugResetForTesting();
      await unresolvedDeletion.close();
      await directory.delete(recursive: true);
    });

    expect(supabase.uid, isNull);
    expect((await unresolvedDeletion.loadRuns()).single.id, 'run-1');
    expect(await unresolvedDeletion.loadDetail('run-1'), isNotNull);
  });
}

RunSummary _run(String id) => RunSummary(
  id: id,
  date: DateTime.parse(
    id == 'run-1' ? '2026-07-14T10:00:00Z' : '2026-07-14T11:00:00Z',
  ),
  distanceKm: 12.4,
  durationSeconds: 900,
  routeName: 'Test route',
  weatherEmoji: '',
  tempDisplay: '',
);

RouteFeedback _feedback(String id, String runId) => RouteFeedback(
  id: id,
  runId: runId,
  routeId: 'route-1',
  routeName: 'Test route',
  feedbackType: 'liked',
  createdAt: DateTime.parse('2026-07-14T10:15:00Z'),
);

RunTelemetryDetail _detail(String runId) => RunTelemetryDetail(
  runId: runId,
  version: 1,
  routeSnapshot: const {'id': 'route-1'},
  samples: const [
    TelemetrySample(
      tMs: 0,
      lat: 45,
      lng: -73,
      speedKmh: 40,
      lateralG: 0.1,
      longitudinalG: 0.02,
      driveMode: 'cruise',
    ),
  ],
  sharpEvents: const [],
  driveModeSeconds: const {'cruise': 1},
  weather: const {},
  createdAt: DateTime.parse('2026-07-14T10:15:00Z'),
);

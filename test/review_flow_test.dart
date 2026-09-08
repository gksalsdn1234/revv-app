import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:revv_app/main.dart';
import 'package:revv_app/models/run_session.dart';
import 'package:revv_app/models/run_summary.dart';
import 'package:revv_app/models/run_telemetry_detail.dart';
import 'package:revv_app/screens/lean_run_summary_screen.dart';
import 'package:revv_app/services/run_history_service.dart';
import 'package:revv_app/services/run_recovery_store.dart';
import 'package:revv_app/services/run_session_service.dart';
import 'package:revv_app/services/settings_service.dart';
import 'package:revv_app/services/location_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'bootstrap draws before initialization and retries a failed load',
    (tester) async {
      final loading = Completer<Widget>();
      var attempts = 0;
      await tester.pumpWidget(
        AppBootstrap(
          load: () {
            attempts++;
            return attempts == 1
                ? loading.future
                : Future.value(const MaterialApp(home: Text('ready')));
          },
        ),
      );
      expect(find.text('Preparing REVV'), findsOneWidget);
      loading.completeError(StateError('disk temporarily unavailable'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not prepare the app. Try again.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('ready'), findsOneWidget);
      expect(attempts, 2);
    },
  );

  testWidgets(
    'report loader draws immediately and retries failed detail loading',
    (tester) async {
      final history = RunHistoryService();
      final summary = await history.saveSession(_session);
      final loading = Completer<RunTelemetryDetail?>();
      var attempts = 0;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => SettingsService()),
            ChangeNotifierProvider<RunHistoryService>.value(value: history),
            ChangeNotifierProvider(create: (_) => LocationService()),
          ],
          child: MaterialApp(
            home: RunReportLoader(
              summary: summary,
              loadDetail: () {
                attempts++;
                return attempts == 1 ? loading.future : Future.value(null);
              },
            ),
          ),
        ),
      );
      expect(find.text('Opening your drive'), findsOneWidget);
      loading.completeError(TimeoutException('network stalled'));
      await tester.pumpAndSettle();
      expect(find.text('Could not open this drive.'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.byType(LeanRunSummaryScreen), findsOneWidget);
      expect(attempts, 2);
    },
  );

  testWidgets('save later exits only after a durable recovery copy succeeds', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(375, 667));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = _Recovery();
    final sessions = RunSessionService(recoveryStore: store);
    var returned = false;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsService()),
          ChangeNotifierProvider<RunHistoryService>(
            create: (_) => _FailingHistory(),
          ),
          ChangeNotifierProvider<RunSessionService>.value(value: sessions),
          ChangeNotifierProvider(create: (_) => LocationService()),
        ],
        child: MaterialApp(
          home: LeanRunSummaryScreen(
            session: _session,
            onReturnHome: () => returned = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save later'));
    await tester.pumpAndSettle();
    expect(returned, true);
    expect(store.saved?.deferredSave, true);
    expect(store.saved?.recoveryId, _session.runId);
    expect(store.saved?.toRunSession().duration, _session.duration);
    expect(tester.takeException(), isNull);
  });

  test(
    'permission refresh reflects Settings changes without requesting again',
    () async {
      var status = PermissionStatus.permanentlyDenied;
      var requests = 0;
      final location = LocationService(
        permissionChecker: () async => status,
        permissionRequester: () async {
          requests++;
          return status;
        },
      );
      await location.refreshPermission();
      expect(location.hasPermission, false);
      status = PermissionStatus.granted;
      await location.refreshPermission();
      expect(location.hasPermission, true);
      expect(requests, 0);
      location.dispose();
    },
  );
}

final _session = RunSession(
  runId: '6c5d04e0-9547-4890-b71d-953b294e299f',
  startTime: DateTime.utc(2026, 9, 8),
  endTime: DateTime.utc(2026, 9, 8, 0, 1),
  maxSpeedKmh: 30,
  avgSpeedKmh: 20,
  distanceKm: 0.2,
  gpsPath: const [],
  weatherEmoji: '',
  tempDisplay: '',
  weatherDesc: '',
);

class _FailingHistory extends RunHistoryService {
  @override
  Future<RunSummary> saveSession(RunSession session) async =>
      throw StateError('disk unavailable');
}

class _Recovery extends RunRecoveryStore {
  RunRecoverySnapshot? saved;
  @override
  Future<void> writeSnapshot(RunRecoverySnapshot snapshot) async {
    saved = snapshot;
  }
}

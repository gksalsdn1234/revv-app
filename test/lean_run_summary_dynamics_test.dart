import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:revv_app/core/app_language.dart';
import 'package:revv_app/models/run_summary.dart';
import 'package:revv_app/models/run_telemetry_detail.dart';
import 'package:revv_app/screens/lean_run_summary_screen.dart';
import 'package:revv_app/services/drive_dynamics_tracker.dart';
import 'package:revv_app/services/run_history_service.dart';
import 'package:revv_app/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('renders dynamics summary line without forbidden words', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => RunHistoryService()),
          ChangeNotifierProvider(create: (_) => SettingsService()),
        ],
        child: MaterialApp(
          home: LeanRunSummaryScreen.history(
            summary: _summary(),
            detail: _detailWithEvents(),
          ),
        ),
      ),
    );
    await tester.pump();

    final text = tester.widget<Text>(
      find.byKey(const ValueKey('dynamics-summary-line')),
    );

    expect(text.data, 'Smoothness 23% · Hard brakes 1 · Abrupt steering 1');
    expect(text.data, isNot(contains('MAX')));
    expect(text.data, isNot(contains('BEST')));
    expect(text.data, isNot(contains('record')));
    expect(text.data, isNot(contains('thrill')));
  });

  testWidgets('renders positive dynamics copy when there are no events', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => RunHistoryService()),
          ChangeNotifierProvider(create: (_) => SettingsService()),
        ],
        child: MaterialApp(
          home: LeanRunSummaryScreen.history(
            summary: _summary(),
            detail: _detailWithoutEvents(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('dynamics-summary-line')), findsOneWidget);
    expect(find.text('Smooth drive'), findsOneWidget);
  });

  test('formats dynamics summary in supported languages', () {
    const summary = DriveDynamicsSummary(
      hardBrakeCount: 1,
      harshSteerCount: 0,
      smoothRatio: 0.92,
      p95LateralG: 0.2,
      sampleSeconds: 60,
    );

    expect(
      dynamicsSummaryLine(AppLanguage.korean, summary),
      '부드러움 92% · 급제동 1회 · 급조작 0회',
    );
    expect(
      dynamicsSummaryLine(AppLanguage.english, summary),
      'Smoothness 92% · Hard brakes 1 · Abrupt steering 0',
    );
    expect(
      dynamicsSummaryLine(AppLanguage.french, summary),
      'Fluidité 92 % · Freinages brusques 1 · Coups de volant 0',
    );
  });
}

RunSummary _summary() {
  return RunSummary(
    id: 'run-1',
    date: DateTime.parse('2026-07-07T10:00:00Z'),
    distanceKm: 4.2,
    durationSeconds: 60,
    routeName: 'Summary Route',
    weatherEmoji: '',
    tempDisplay: '',
  );
}

RunTelemetryDetail _detailWithEvents() {
  return _detail(
    samples: const [
      TelemetrySample(
        tMs: 0,
        lat: 0,
        lng: 0,
        speedKmh: 30,
        lateralG: 0,
        longitudinalG: 0,
        driveMode: 'cruise',
      ),
      TelemetrySample(
        tMs: 200,
        lat: 0,
        lng: 0,
        speedKmh: 31,
        lateralG: 0.2,
        longitudinalG: 0,
        driveMode: 'cruise',
      ),
      TelemetrySample(
        tMs: 600,
        lat: 0,
        lng: 0,
        speedKmh: 31,
        lateralG: 0.2,
        longitudinalG: -0.4,
        driveMode: 'cruise',
      ),
      TelemetrySample(
        tMs: 1000,
        lat: 0,
        lng: 0,
        speedKmh: 32,
        lateralG: 0.2,
        longitudinalG: -0.4,
        driveMode: 'cruise',
      ),
      TelemetrySample(
        tMs: 1300,
        lat: 0,
        lng: 0,
        speedKmh: 32,
        lateralG: 0.2,
        longitudinalG: 0,
        driveMode: 'cruise',
      ),
    ],
  );
}

RunTelemetryDetail _detailWithoutEvents() {
  return _detail(
    samples: const [
      TelemetrySample(
        tMs: 0,
        lat: 0,
        lng: 0,
        speedKmh: 30,
        lateralG: 0.1,
        longitudinalG: 0,
        driveMode: 'cruise',
      ),
      TelemetrySample(
        tMs: 1000,
        lat: 0,
        lng: 0,
        speedKmh: 31,
        lateralG: 0.1,
        longitudinalG: 0,
        driveMode: 'cruise',
      ),
    ],
  );
}

RunTelemetryDetail _detail({required List<TelemetrySample> samples}) {
  return RunTelemetryDetail(
    runId: 'run-1',
    version: RunTelemetryDetail.currentVersion,
    routeSnapshot: null,
    samples: samples,
    sharpEvents: const [],
    driveModeSeconds: const {},
    weather: const {},
    createdAt: DateTime.parse('2026-07-07T10:00:00Z'),
  );
}

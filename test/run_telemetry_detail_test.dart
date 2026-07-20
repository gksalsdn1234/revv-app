import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/models/run_session.dart';
import 'package:revv_app/models/run_telemetry_detail.dart';

void main() {
  test('single-sample spike is rejected as noise', () {
    // Given: first-sample spikes followed by raw zero-G samples.
    final brakingSession = _session([
      _sample(0, speedKmh: 30, longitudinalG: -1),
      _sample(100, speedKmh: 30),
      _sample(200, speedKmh: 30),
      _sample(300, speedKmh: 30),
    ]);
    final accelerationSession = _session([
      _sample(0, speedKmh: 30, longitudinalG: 0.8),
      _sample(100, speedKmh: 30),
      _sample(200, speedKmh: 30),
      _sample(300, speedKmh: 30),
    ]);
    final sharpSession = _session([
      _sample(0, speedKmh: 30, lateralG: 1.5),
      _sample(100, speedKmh: 30),
      _sample(200, speedKmh: 30),
      _sample(300, speedKmh: 30),
    ]);

    // When: detail analytics are derived.
    final brakingDetail = RunTelemetryDetail.fromSession(
      'run-braking-spike',
      brakingSession,
    );
    final accelerationDetail = RunTelemetryDetail.fromSession(
      'run-acceleration-spike',
      accelerationSession,
    );
    final sharpDetail = RunTelemetryDetail.fromSession(
      'run-sharp-spike',
      sharpSession,
    );

    // Then: one-sample threshold crossings do not become events.
    expect(brakingDetail.analytics['brakingEventCount'], 0);
    expect(accelerationDetail.analytics['accelerationEventCount'], 0);
    expect(sharpDetail.analytics['sharpEventCount'], 0);
  });

  test('event gates use smoothed thresholds with raw support', () {
    // Given: raw threshold crossings separated by a neutral sample, but the
    // smoothed signal stays over each event threshold for 200 ms.
    final brakingSession = _session([
      _sample(0, speedKmh: 30, longitudinalG: -0.7),
      _sample(100, speedKmh: 30),
      _sample(200, speedKmh: 30, longitudinalG: -0.7),
      _sample(300, speedKmh: 30),
    ]);
    final accelerationSession = _session([
      _sample(0, speedKmh: 30, longitudinalG: 0.6),
      _sample(100, speedKmh: 30),
      _sample(200, speedKmh: 30, longitudinalG: 0.6),
      _sample(300, speedKmh: 30),
    ]);
    final sharpSession = _session([
      _sample(0, speedKmh: 30, lateralG: 1),
      _sample(100, speedKmh: 30),
      _sample(200, speedKmh: 30, lateralG: 1),
      _sample(300, speedKmh: 30),
    ]);

    // When: detail analytics are derived.
    final brakingDetail = RunTelemetryDetail.fromSession(
      'run-smoothed-braking',
      brakingSession,
    );
    final accelerationDetail = RunTelemetryDetail.fromSession(
      'run-smoothed-acceleration',
      accelerationSession,
    );
    final sharpDetail = RunTelemetryDetail.fromSession(
      'run-smoothed-sharp',
      sharpSession,
    );

    // Then: smoothed sustained crossings count even when raw samples dip.
    expect(brakingDetail.analytics['brakingEventCount'], 1);
    expect(accelerationDetail.analytics['accelerationEventCount'], 1);
    expect(sharpDetail.analytics['sharpEventCount'], 1);
  });

  test('sustained crossing counts as one event', () {
    // Given: one sustained braking run with multiple threshold samples.
    final session = _session([
      _sample(0, speedKmh: 30),
      _sample(100, speedKmh: 30, longitudinalG: -0.7),
      _sample(200, speedKmh: 30, longitudinalG: -0.7),
      _sample(300, speedKmh: 30, longitudinalG: -0.7),
      _sample(400, speedKmh: 30),
    ]);

    // When: detail analytics are derived.
    final detail = RunTelemetryDetail.fromSession('run-sustained', session);

    // Then: the sustained run is counted once, not once per sample.
    expect(detail.analytics['brakingEventCount'], 1);
    expect(detail.analytics['accelerationEventCount'], 0);
    expect(detail.analytics['sharpEventCount'], 0);
  });

  test('sustained acceleration and sharp crossings count once', () {
    // Given: sustained threshold runs for acceleration and sharp lateral G.
    final accelerationSession = _session([
      _sample(0, speedKmh: 30),
      _sample(100, speedKmh: 30, longitudinalG: 0.4),
      _sample(200, speedKmh: 30, longitudinalG: 0.4),
      _sample(300, speedKmh: 30, longitudinalG: 0.4),
      _sample(400, speedKmh: 30),
    ]);
    final sharpSession = _session([
      _sample(0, speedKmh: 30),
      _sample(100, speedKmh: 30, lateralG: 1),
      _sample(200, speedKmh: 30, lateralG: 1),
      _sample(300, speedKmh: 30, lateralG: 1),
      _sample(400, speedKmh: 30),
    ]);

    // When: detail analytics are derived.
    final accelerationDetail = RunTelemetryDetail.fromSession(
      'run-acceleration-sustained',
      accelerationSession,
    );
    final sharpDetail = RunTelemetryDetail.fromSession(
      'run-sharp-sustained',
      sharpSession,
    );

    // Then: each sustained run is counted once.
    expect(accelerationDetail.analytics['accelerationEventCount'], 1);
    expect(sharpDetail.analytics['sharpEventCount'], 1);
  });

  test('sharp corner fallback only applies without telemetry', () {
    // Given: legacy sharp corner data paired with either empty or weak telemetry.
    final sharpCorner = SharpCorner(
      position: const LatLng(45, -73),
      lateralG: 1,
      speedKmh: 30,
      time: DateTime.parse('2026-06-29T12:00:00Z'),
    );
    final telemetryBackedSession = _session(
      [_sample(0, speedKmh: 30, lateralG: 1)],
      sharpCorners: [sharpCorner],
    );
    final emptyTelemetrySession = _session(
      const [],
      sharpCorners: [sharpCorner],
    );

    // When: detail analytics are derived.
    final telemetryBackedDetail = RunTelemetryDetail.fromSession(
      'run-telemetry-backed-sharp',
      telemetryBackedSession,
    );
    final emptyTelemetryDetail = RunTelemetryDetail.fromSession(
      'run-empty-telemetry-sharp',
      emptyTelemetrySession,
    );

    // Then: telemetry-backed sharp counts still require sustained telemetry.
    expect(telemetryBackedDetail.analytics['sharpEventCount'], 0);
    expect(emptyTelemetryDetail.analytics['sharpEventCount'], 1);
  });

  test('low-speed samples do not bypass event gates', () {
    // Given: sustained threshold crossings below the speed gates.
    final brakingSession = _session([
      _sample(0, speedKmh: 4),
      _sample(100, speedKmh: 4, longitudinalG: -0.7),
      _sample(200, speedKmh: 4, longitudinalG: -0.7),
      _sample(300, speedKmh: 4, longitudinalG: -0.7),
    ]);
    final accelerationSession = _session([
      _sample(0, speedKmh: 4),
      _sample(100, speedKmh: 4, longitudinalG: 0.5),
      _sample(200, speedKmh: 4, longitudinalG: 0.5),
      _sample(300, speedKmh: 4, longitudinalG: 0.5),
    ]);
    final sharpSession = _session([
      _sample(0, speedKmh: 10),
      _sample(100, speedKmh: 10, lateralG: 0.7),
      _sample(200, speedKmh: 10, lateralG: 0.7),
      _sample(300, speedKmh: 10, lateralG: 0.7),
    ]);

    // When: detail analytics are derived.
    final brakingDetail = RunTelemetryDetail.fromSession(
      'run-low-speed-braking',
      brakingSession,
    );
    final accelerationDetail = RunTelemetryDetail.fromSession(
      'run-low-speed-acceleration',
      accelerationSession,
    );
    final sharpDetail = RunTelemetryDetail.fromSession(
      'run-low-speed-sharp',
      sharpSession,
    );

    // Then: threshold crossings below speed gates do not count.
    expect(brakingDetail.analytics['brakingEventCount'], 0);
    expect(accelerationDetail.analytics['accelerationEventCount'], 0);
    expect(sharpDetail.analytics['sharpEventCount'], 0);
  });

  test('low-speed raw spikes do not smear into high-speed events', () {
    // Given: low-speed raw spikes followed by high-speed zero-G samples.
    final brakingSession = _session([
      _sample(100, speedKmh: 4, longitudinalG: -1),
      _sample(250, speedKmh: 4, longitudinalG: -1),
      _sample(300, speedKmh: 30),
      _sample(450, speedKmh: 30),
    ]);
    final accelerationSession = _session([
      _sample(100, speedKmh: 4, longitudinalG: 1),
      _sample(250, speedKmh: 4, longitudinalG: 1),
      _sample(300, speedKmh: 30),
      _sample(450, speedKmh: 30),
    ]);
    final sharpSession = _session([
      _sample(100, speedKmh: 4, lateralG: 1.5),
      _sample(250, speedKmh: 4, lateralG: 1.5),
      _sample(300, speedKmh: 30),
      _sample(450, speedKmh: 30),
    ]);

    // When: smoothing carries the low-speed G into high-speed samples.
    final brakingDetail = RunTelemetryDetail.fromSession(
      'run-speed-gate-smear-braking',
      brakingSession,
    );
    final accelerationDetail = RunTelemetryDetail.fromSession(
      'run-speed-gate-smear-acceleration',
      accelerationSession,
    );
    final sharpDetail = RunTelemetryDetail.fromSession(
      'run-speed-gate-smear-sharp',
      sharpSession,
    );

    // Then: raw support still has to satisfy each event speed gate.
    expect(brakingDetail.analytics['brakingEventCount'], 0);
    expect(accelerationDetail.analytics['accelerationEventCount'], 0);
    expect(sharpDetail.analytics['sharpEventCount'], 0);
  });

  test('p95 values are computed from smoothed samples', () {
    // Given: a one-sample lateral G spike that smoothing should dilute.
    final session = _session([
      _sample(0, speedKmh: 30),
      _sample(100, speedKmh: 30, lateralG: 1),
      _sample(200, speedKmh: 30),
    ]);

    // When: detail analytics are derived.
    final detail = RunTelemetryDetail.fromSession('run-p95', session);

    // Then: p95 uses smoothed G, not the raw 1.0G spike.
    expect(detail.analytics['p95AbsLateralG'], closeTo(0.5, 0.0001));
  });

  test('empty telemetry stays finite', () {
    // Given: sessions with no telemetry and one telemetry sample.
    final emptySession = _session(const []);
    final shortSession = _session([_sample(0, speedKmh: 30, lateralG: 0.2)]);

    // When: detail analytics are derived.
    final emptyDetail = RunTelemetryDetail.fromSession(
      'run-empty',
      emptySession,
    );
    final shortDetail = RunTelemetryDetail.fromSession(
      'run-short',
      shortSession,
    );

    // Then: malformed short input does not produce NaN or infinity.
    for (final key in [
      'avgAbsLateralG',
      'p95AbsLateralG',
      'avgAbsLongitudinalG',
      'p95AbsLongitudinalG',
      'windingSamplePct',
    ]) {
      expect((emptyDetail.analytics[key] as num).isFinite, isTrue);
      expect((shortDetail.analytics[key] as num).isFinite, isTrue);
    }
  });

  test('scores use fixed REVV metric formulas', () {
    // Given: fixture inputs chosen to produce exact plan-contract scores.
    final samples = [
      _sample(0, speedKmh: 30, lateralG: 0.3, longitudinalG: 0.1),
      _sample(100, speedKmh: 30, lateralG: 0.3, longitudinalG: 0.1),
      _sample(200, speedKmh: 30, lateralG: 0.3, longitudinalG: 0.1),
      _sample(300, speedKmh: 30, lateralG: 0.3, longitudinalG: 0.1),
    ];
    final session = _session(
      samples,
      duration: const Duration(minutes: 10),
      maxSpeedKmh: 30,
      route: _route(tightCurveKm: 1.25, mediumCurveKm: 2, maxContinuousKm: 2),
      driveModeSeconds: const {'winding': 300},
    );
    final fastSession = _session(
      samples,
      duration: const Duration(minutes: 10),
      maxSpeedKmh: 180,
      route: _route(tightCurveKm: 1.25, mediumCurveKm: 2, maxContinuousKm: 2),
      driveModeSeconds: const {'winding': 300},
    );

    // When: detail analytics are derived.
    final analytics = RunTelemetryDetail.fromSession(
      'run-score-formulas',
      session,
    ).analytics;
    final fastAnalytics = RunTelemetryDetail.fromSession(
      'run-score-formulas-fast',
      fastSession,
    ).analytics;

    // Then: score values match the fixed formula contract exactly.
    expect(analytics['windingSamplePct'], 100);
    expect(analytics['technicalScore'], 52);
    expect(analytics['smoothnessScore'], 94);
    expect(analytics['flowScoreDisplay'], 70);
    expect(analytics['revvScore'], 81);
    expect(fastAnalytics['technicalScore'], analytics['technicalScore']);
    expect(fastAnalytics['smoothnessScore'], analytics['smoothnessScore']);
    expect(fastAnalytics['flowScoreDisplay'], analytics['flowScoreDisplay']);
    expect(fastAnalytics['revvScore'], analytics['revvScore']);
  });

  test('scores stay finite with empty denominators', () {
    // Given: no samples, no route, and zero duration.
    final session = _session(const [], duration: Duration.zero);

    // When: detail analytics are derived.
    final analytics = RunTelemetryDetail.fromSession(
      'run-empty-score-formulas',
      session,
    ).analytics;

    // Then: denominator guards produce exact finite score values.
    expect(analytics['windingSamplePct'], 0);
    expect(analytics['technicalScore'], 0);
    expect(analytics['smoothnessScore'], 100);
    expect(analytics['flowScoreDisplay'], 15);
    expect(analytics['revvScore'], 29);
  });

  test('derives rich non-OBD ride metrics', () {
    // Given: a completed non-OBD run with GPS, IMU, route, mode, and weather data.
    final session = _session(
      [
        _sample(0, speedKmh: 0, lateralG: 0.3, longitudinalG: 0.1),
        _sample(250, speedKmh: 40, lateralG: 0.3, longitudinalG: 0.1),
        _sample(500, speedKmh: 50, lateralG: 0.3, longitudinalG: 0.1),
        _sample(750, speedKmh: 60, lateralG: 0.3, longitudinalG: 0.1),
        _sample(1000, speedKmh: 70, lateralG: 0.3, longitudinalG: 0.1),
      ],
      duration: const Duration(seconds: 100),
      distanceKm: 2.4,
      maxSpeedKmh: 92,
      avgSpeedKmh: 48,
      gpsPath: const [
        LatLng(45, -73),
        LatLng(45.01, -73.01),
        LatLng(45.02, -73.02),
      ],
      route: _route(tightCurveKm: 1, mediumCurveKm: 1, maxContinuousKm: 1),
      maxLateralG: 0.32,
      maxLonG: -0.2,
      driveModeSeconds: const {'cruise': 60, 'winding': 40},
    );

    // When: detail analytics are derived.
    final detail = RunTelemetryDetail.fromSession('run-rich-contract', session);
    final json = detail.toJson();
    final restored = RunTelemetryDetail.fromJson(json);
    final analytics = detail.analytics;

    // Then: the versioned internal contract exposes rich non-OBD metrics.
    expect(detail.version, RunTelemetryDetail.currentVersion);
    expect(json['version'], RunTelemetryDetail.currentVersion);
    expect(restored.analytics.keys, containsAll(analytics.keys));
    expect(detail.weather, {
      'emoji': 'Clear',
      'tempDisplay': '18C',
      'description': 'Clear',
    });
    expect(analytics, containsPair('durationSeconds', 100));
    expect(analytics, containsPair('movingDurationSeconds', 80));
    expect(analytics, containsPair('idleDurationSeconds', 20));
    expect(analytics, containsPair('distanceKm', 2.4));
    expect(analytics, containsPair('routeCompletionPct', 48));
    expect(analytics, containsPair('sampleCount', 5));
    expect(analytics, containsPair('gpsPointCount', 3));
    expect(analytics, containsPair('avgSpeedKmh', 48));
    expect(analytics, containsPair('avgMovingSpeedKmh', 55));
    expect(analytics, containsPair('maxSpeedKmh', 92));
    expect(analytics, containsPair('maxLateralG', 0.32));
    expect(analytics, containsPair('maxLongitudinalG', -0.2));
    expect(analytics, containsPair('peakG', 0.32));
    expect(analytics['avgAbsLateralG'], closeTo(0.3, 0.0001));
    expect(analytics['p95AbsLateralG'], closeTo(0.3, 0.0001));
    expect(analytics['avgAbsLongitudinalG'], closeTo(0.1, 0.0001));
    expect(analytics['p95AbsLongitudinalG'], closeTo(0.1, 0.0001));
    expect(analytics, containsPair('brakingEventCount', 0));
    expect(analytics, containsPair('accelerationEventCount', 0));
    expect(analytics, containsPair('sharpEventCount', 0));
    expect(analytics, containsPair('windingSamplePct', 80));
    expect(
      analytics,
      containsPair('driveModeSeconds', {'cruise': 60, 'winding': 40}),
    );
    expect(analytics, containsPair('technicalScore', 42));
    expect(analytics, containsPair('smoothnessScore', 94));
    expect(analytics, containsPair('flowScoreDisplay', 50));
    expect(analytics, containsPair('revvScore', 68));
    expect(
      analytics.keys.where((key) => key.toLowerCase().contains('obd')),
      isEmpty,
    );
    expect(
      analytics.keys.where(
        (key) => key.toLowerCase().contains('publicmaxspeed'),
      ),
      isEmpty,
    );
  });

  test('old telemetry detail json loads without rich analytics fields', () {
    // Given: a legacy detail payload with no version, analytics, samples,
    // drive-mode, or weather keys.
    final legacy = <String, dynamic>{
      'runId': 'legacy-run',
      'createdAt': '2026-06-29T12:00:00Z',
    };

    // When: the detail is restored.
    final detail = RunTelemetryDetail.fromJson(legacy);

    // Then: missing rich fields are tolerated instead of rejected.
    expect(detail.runId, 'legacy-run');
    expect(detail.version, RunTelemetryDetail.currentVersion);
    expect(detail.samples, isEmpty);
    expect(detail.sharpEvents, isEmpty);
    expect(detail.analytics, isEmpty);
    expect(detail.driveModeSeconds, isEmpty);
    expect(detail.weather, isEmpty);
  });

  test('rich ride metrics stay finite with empty telemetry', () {
    // Given: an empty non-OBD run with no route, GPS, or elapsed time.
    final session = _session(
      const [],
      duration: Duration.zero,
      distanceKm: 0,
      maxSpeedKmh: 0,
      avgSpeedKmh: 0,
      maxLateralG: 0,
      maxLonG: 0,
    );

    // When: detail analytics are derived.
    final analytics = RunTelemetryDetail.fromSession(
      'run-empty-rich-contract',
      session,
    ).analytics;

    // Then: all numeric rich metrics are finite and empty-derived values are zero.
    for (final key in [
      'durationSeconds',
      'movingDurationSeconds',
      'idleDurationSeconds',
      'distanceKm',
      'routeCompletionPct',
      'sampleCount',
      'gpsPointCount',
      'avgSpeedKmh',
      'avgMovingSpeedKmh',
      'maxSpeedKmh',
      'maxLateralG',
      'maxLongitudinalG',
      'peakG',
      'avgAbsLateralG',
      'p95AbsLateralG',
      'avgAbsLongitudinalG',
      'p95AbsLongitudinalG',
      'brakingEventCount',
      'accelerationEventCount',
      'sharpEventCount',
      'windingSamplePct',
    ]) {
      expect((analytics[key] as num).isFinite, isTrue, reason: key);
      expect(analytics[key], 0, reason: key);
    }
    for (final key in [
      'technicalScore',
      'smoothnessScore',
      'flowScoreDisplay',
      'revvScore',
    ]) {
      expect((analytics[key] as num).isFinite, isTrue, reason: key);
    }
    expect(analytics['driveModeSeconds'], isEmpty);
    expect(
      analytics.keys.where((key) => key.toLowerCase().contains('obd')),
      isEmpty,
    );
  });
  test('stored telemetry is bounded while preserving both endpoints', () {
    final sampleCount = RunTelemetryDetail.maxStoredSamples + 2;
    final samples = List.generate(
      sampleCount,
      (index) => _sample(index * 1000, speedKmh: 30),
      growable: false,
    );

    final detail = RunTelemetryDetail.fromSession(
      'bounded-run',
      _session(samples, duration: Duration(seconds: sampleCount)),
    );

    expect(detail.samples, hasLength(RunTelemetryDetail.maxStoredSamples));
    expect(detail.samples.first.tMs, samples.first.tMs);
    expect(detail.samples.last.tMs, samples.last.tMs);
    expect(detail.analytics['sampleCount'], sampleCount);
  });
}

RunSession _session(
  List<TelemetrySample> samples, {
  List<SharpCorner> sharpCorners = const [],
  Duration duration = const Duration(seconds: 1),
  double distanceKm = 0.1,
  double maxSpeedKmh = 30,
  double avgSpeedKmh = 30,
  List<LatLng> gpsPath = const [],
  RevvRoute? route,
  double maxLateralG = 1,
  double maxLonG = 1,
  Map<String, int> driveModeSeconds = const {},
}) {
  final start = DateTime.parse('2026-06-29T12:00:00Z');
  return RunSession(
    startTime: start,
    endTime: start.add(duration),
    maxSpeedKmh: maxSpeedKmh,
    avgSpeedKmh: avgSpeedKmh,
    distanceKm: distanceKm,
    gpsPath: gpsPath,
    route: route,
    weatherEmoji: 'Clear',
    tempDisplay: '18C',
    weatherDesc: 'Clear',
    maxLateralG: maxLateralG,
    maxLonG: maxLonG,
    driveModeSeconds: driveModeSeconds,
    sharpCorners: sharpCorners,
    telemetrySamples: samples,
  );
}

RevvRoute _route({
  required double tightCurveKm,
  required double mediumCurveKm,
  required double maxContinuousKm,
}) {
  return RevvRoute(
    id: 'route-score-fixture',
    name: 'Score Fixture',
    nodes: const [LatLng(45, -73), LatLng(45.01, -73.01)],
    distanceKm: 5,
    windingScore: 6,
    starRating: 4,
    centerPoint: const LatLng(45, -73),
    distanceFromUser: 0,
    sharpCurveCount: 0,
    tightCurveKm: tightCurveKm,
    mediumCurveKm: mediumCurveKm,
    maxContinuousKm: maxContinuousKm,
  );
}

TelemetrySample _sample(
  int tMs, {
  double speedKmh = 0,
  double lateralG = 0,
  double longitudinalG = 0,
}) {
  return TelemetrySample(
    tMs: tMs,
    lat: 45,
    lng: -73,
    speedKmh: speedKmh,
    lateralG: lateralG,
    longitudinalG: longitudinalG,
    driveMode: 'cruise',
  );
}

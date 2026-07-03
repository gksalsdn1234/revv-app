import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/models/run_session.dart';
import 'package:revv_app/models/run_summary.dart';
import 'package:revv_app/models/run_telemetry_detail.dart';
import 'package:revv_app/ui/run_share_card_content.dart';
import 'package:revv_app/ui/run_share_metrics.dart';

void main() {
  test('builds safe share metrics from telemetry detail', () {
    // Given: telemetry detail has the rich analytics and private internals.
    final metrics = buildRunShareMetrics(
      session: _session(),
      summary: _summary(),
      detail: _detail(),
    );

    // When: default share metrics are rendered as label/value pairs.
    final shareMetrics = {
      for (final metric in metrics.defaultShareMetrics)
        metric.label: metric.value,
    };

    // Then: the safe display contract is present without private fields.
    expect(shareMetrics['REVV Score'], '68');
    expect(shareMetrics['Flow'], '50');
    expect(shareMetrics['Technical'], '73');
    expect(shareMetrics['Smoothness'], '80');
    expect(shareMetrics['Winding'], '43%');
    expect(shareMetrics['Corner events'], '4');
    expect(shareMetrics['Route'], '88% done');
    expect(shareMetrics['Distance'], '12.3 km');
    expect(shareMetrics['Duration'], '12m 34s');
    expect(shareMetrics['Max speed'], isNull);
    expect(metrics.maxSpeedInternalOnly.value, '181 km/h');
    expect(metrics.maxSpeedInternalOnly.internalOnly, isTrue);
  });

  test('default share metrics hide max speed', () {
    // Given: session, summary, and detail all contain max speed.
    final metrics = buildRunShareMetrics(
      session: _session(),
      summary: _summary(),
      detail: _detail(),
    );
    final content = buildRunShareCardContent(
      preset: ShareCardPreset.square,
      summary: _summary(),
      detail: _detail(),
      session: _session(),
    );

    // When: default/export-visible text is collected.
    final metricText = metrics.defaultShareMetrics
        .expand((metric) => [metric.label, metric.value])
        .join(' | ');
    final cardText = content.visibleText.join(' | ');

    // Then: max speed remains available only as an internal metric.
    expect(metricText, isNot(contains('181')));
    expect(metricText, isNot(contains('Max speed')));
    expect(cardText, isNot(contains('181')));
    expect(cardText, isNot(contains('Max speed')));
    expect(metrics.maxSpeedInternalOnly.value, '181 km/h');
  });

  test('default share metrics avoid record-framed safety copy', () {
    // Given: metrics include telemetry fields that stay internal.
    final metrics = buildRunShareMetrics(
      session: _session(),
      summary: _summary(),
      detail: _detail(),
    );

    // When: public labels and values are collected.
    final visibleText = metrics.defaultShareMetrics
        .expand((metric) => [metric.label, metric.value])
        .join(' | ');

    // Then: public metric copy does not use record or limit framing.
    expect(
      visibleText,
      isNot(
        matches(
          RegExp(
            r'\b(MAX|BEST|PEAK|PK|RECORD)\b|GRIP LIMIT|Attack|어택|최고|최대|신기록|0\.45G',
            caseSensitive: false,
          ),
        ),
      ),
    );
  });

  test('summary-only share metrics stay finite and safe', () {
    // Given: detail is missing, but summary/session still have headline data.
    final metrics = buildRunShareMetrics(
      session: _session(),
      summary: _summary(),
    );

    // When: default share metrics are built from safe fallback fields.
    final shareMetrics = {
      for (final metric in metrics.defaultShareMetrics)
        metric.label: metric.value,
    };

    // Then: no placeholder raw data or max speed leaks.
    expect(shareMetrics['Distance'], '12.3 km');
    expect(shareMetrics['Duration'], '12m 34s');
    expect(shareMetrics['Route'], '91% done');
    expect(shareMetrics['Corner events'], '4');
    expect(shareMetrics['Max speed'], isNull);
  });
}

RunSession _session() {
  return RunSession(
    startTime: DateTime.parse('2026-06-30T12:00:00Z'),
    endTime: DateTime.parse('2026-06-30T12:12:34Z'),
    maxSpeedKmh: 180.7,
    avgSpeedKmh: 58.4,
    distanceKm: 12.3,
    gpsPath: const [LatLng(45.0, -73.0), LatLng(45.1, -73.1)],
    route: _route(),
    weatherEmoji: 'sunny',
    tempDisplay: '22 C',
    weatherDesc: 'clear',
    maxLateralG: 0.64,
    maxLonG: -0.52,
  );
}

RunSummary _summary() {
  return RunSummary(
    id: 'run-safe',
    date: DateTime.parse('2026-06-30T12:12:34Z'),
    distanceKm: 12.3,
    durationSeconds: 754,
    maxSpeedKmh: 180.7,
    avgSpeedKmh: 58.4,
    routeName: 'Forest Sweep',
    routeId: 'route-safe',
    weatherEmoji: 'sunny',
    tempDisplay: '22 C',
    maxLateralG: 0.64,
    maxLongitudinalG: -0.52,
    sharpCornersCount: 4,
    routeDistanceKm: 13.5,
    routeCompletionPct: 91,
  );
}

RunTelemetryDetail _detail() {
  return RunTelemetryDetail(
    runId: 'run-safe',
    version: RunTelemetryDetail.currentVersion,
    routeSnapshot: const {
      'name': 'Forest Sweep',
      'nodes': [
        {'lat': 45.0, 'lng': -73.0},
        {'lat': 45.1, 'lng': -73.1},
      ],
    },
    samples: const [],
    sharpEvents: const [],
    analytics: const {
      'revvScore': 68,
      'flowScoreDisplay': 50,
      'technicalScore': 73,
      'smoothnessScore': 80,
      'windingSamplePct': 42.6,
      'sharpEventCount': 4,
      'peakG': 0.62,
      'p95AbsLateralG': 0.31,
      'routeCompletionPct': 88,
      'maxSpeedKmh': 180.7,
    },
    driveModeSeconds: const {},
    weather: const {'description': 'clear'},
    createdAt: DateTime(2026, 6, 30, 12, 13),
  );
}

RevvRoute _route() {
  return const RevvRoute(
    id: 'route-safe',
    name: 'Forest Sweep',
    nodes: [LatLng(45.0, -73.0), LatLng(45.1, -73.1)],
    distanceKm: 13.5,
    windingScore: 4,
    starRating: 4,
    sharpCurveCount: 7,
    centerPoint: LatLng(45.05, -73.05),
    distanceFromUser: 3,
    tightCurveKm: 1.1,
    mediumCurveKm: 4.6,
    maxContinuousKm: 3.4,
  );
}

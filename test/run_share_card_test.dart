import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/models/run_summary.dart';
import 'package:revv_app/models/run_telemetry_detail.dart';
import 'package:revv_app/ui/run_share_card_content.dart';

void main() {
  test('share card content uses safe default metrics', () {
    // Given: rich private telemetry exists for a completed run.
    final content = buildRunShareCardContent(
      preset: ShareCardPreset.square,
      summary: _summary(),
      detail: _detailWithSamples(sampleCount: 300),
    );

    // When: the static share-card content contract is built.
    final chipLabels = content.metricChips.map((metric) => metric.label);
    final listLabels = content.metricList.map((metric) => metric.label);

    // Then: public card fields are safe, preset-aware, and bounded.
    expect(content.presetInfo.aspectRatio, 1);
    expect(content.presetInfo.isCompact, isFalse);
    expect(content.presetInfo.background, ShareCardBackground.solid);
    expect(content.routeName, 'Forest Sweep');
    expect(content.dateLabel, 'Jun 30, 2026');
    expect(content.title, 'Forest Sweep');
    expect(content.subtitle, contains('Jun 30, 2026'));
    expect(chipLabels, containsAll(['Distance', 'Duration', 'REVV Score']));
    expect(listLabels, containsAll(['Flow', 'Smoothness', 'Winding']));
    expect(content.pathPreview, isNotNull);
    expect(content.pathPreview!.length, lessThanOrEqualTo(240));
    expect(
      content.pathPreview!.every(
        (point) => point.x >= 0 && point.x <= 1 && point.y >= 0 && point.y <= 1,
      ),
      isTrue,
    );
  });

  test('share card default content hides max speed and raw coordinates', () {
    // Given: summary and detail contain max speed, exact endpoints, samples,
    // route nodes, and OBD-shaped private data.
    final content = buildRunShareCardContent(
      preset: ShareCardPreset.story,
      summary: _summary(routeName: 'OBD-II 45.123456 Loop'),
      detail: _detailWithSamples(sampleCount: 300),
    );

    // When: public text and preview path data are inspected.
    final visibleText = content.visibleText.join(' | ');
    final previewText = content.pathPreview!
        .map(
          (point) =>
              '${point.x.toStringAsFixed(6)},${point.y.toStringAsFixed(6)}',
        )
        .join(' | ');

    // Then: unsafe values never appear in public text or preview data.
    for (final value in _unsafeValues) {
      expect(visibleText, isNot(contains(value)), reason: 'text leaked $value');
      expect(previewText, isNot(contains(value)), reason: 'path leaked $value');
    }
    expect(content.routeName, 'Private route');
    expect(content.presetInfo.aspectRatio, 9 / 16);
    expect(content.pathPreview!.length, 240);
  });

  test('share card sticker preset is compact and solid', () {
    // Given: a sticker share preset is requested.
    final content = buildRunShareCardContent(
      preset: ShareCardPreset.sticker,
      summary: _summary(),
      detail: _detailWithSamples(sampleCount: 12),
    );

    // When/Then: the contract declares a compact solid sticker, no renderer
    // or transparent export required.
    expect(content.presetInfo.isCompact, isTrue);
    expect(content.presetInfo.background, ShareCardBackground.solid);
    expect(content.presetInfo.aspectRatio, 1);
    expect(content.metricChips.length, lessThanOrEqualTo(4));
  });
}

const _unsafeValues = [
  '214.6',
  '214.60',
  '215',
  'Max speed',
  'max speed',
  '45.123456',
  '-73.123456',
  '45.654321',
  '-73.654321',
  '46.111111',
  '-74.111111',
  '47.222222',
  '-75.222222',
  'OBD',
  'OBD-II',
  'RPM',
  'throttle',
  'boost',
];

RunSummary _summary({String routeName = 'Forest Sweep'}) {
  return RunSummary(
    id: 'run-safe',
    date: DateTime.parse('2026-06-30T12:12:34Z'),
    distanceKm: 12.3,
    durationSeconds: 754,
    maxSpeedKmh: 214.6,
    avgSpeedKmh: 58.4,
    routeName: routeName,
    routeId: 'route-safe',
    weatherEmoji: 'sunny',
    tempDisplay: '22 C',
    maxLateralG: 0.64,
    maxLongitudinalG: -0.52,
    routeDistanceKm: 13.5,
    routeCompletionPct: 91,
    startPoint: const LatLng(45.123456, -73.123456),
    endPoint: const LatLng(45.654321, -73.654321),
  );
}

RunTelemetryDetail _detailWithSamples({required int sampleCount}) {
  final samples = List.generate(sampleCount, (index) {
    final progress = index / (sampleCount - 1);
    return TelemetrySample(
      tMs: index * 1000,
      lat: 45.123456 + (45.654321 - 45.123456) * progress,
      lng: -73.123456 + (-73.654321 + 73.123456) * progress,
      speedKmh: index.isEven ? 214.6 : 80,
      lateralG: 0.1,
      longitudinalG: 0.1,
      driveMode: 'winding',
    );
  });

  return RunTelemetryDetail(
    runId: 'run-safe',
    version: RunTelemetryDetail.currentVersion,
    routeSnapshot: const {
      'name': 'RPM Valley',
      'nodes': [
        {'lat': 46.111111, 'lng': -74.111111},
        {'lat': 47.222222, 'lng': -75.222222},
      ],
    },
    samples: samples,
    sharpEvents: const [
      {'lat': 45.123456, 'lng': -73.123456, 'lateralG': 0.7, 'label': 'boost'},
    ],
    analytics: const {
      'revvScore': 68,
      'flowScoreDisplay': 50,
      'technicalScore': 73,
      'smoothnessScore': 80,
      'windingSamplePct': 42.6,
      'peakG': 0.62,
      'p95AbsLateralG': 0.31,
      'routeCompletionPct': 88,
      'maxSpeedKmh': 214.6,
      'obdRpm': 7200,
      'throttle': 91,
      'boost': 14,
    },
    driveModeSeconds: const {'winding': 120},
    weather: const {'description': 'clear'},
    createdAt: DateTime(2026, 6, 30, 12, 13),
  );
}

import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/models/run_summary.dart';
import 'package:revv_app/models/run_telemetry_detail.dart';
import 'package:revv_app/ui/run_share_card_content.dart';

void main() {
  test('share presets redact sensitive fields by default', () {
    for (final preset in ShareCardPreset.values) {
      for (final obdRouteTitle in _obdRouteTitleVariants) {
        // Given: private run data contains every sensitive field the share layer
        // must not expose.
        final content = buildRunShareCardContent(
          preset: preset,
          summary: _summary(routeName: obdRouteTitle),
          detail: _detail(),
        );

        // When: visible share text is gathered for the preset.
        final visibleText = content.visibleText.join(' | ');

        // Then: no sensitive field or OBD-shaped label is present.
        for (final sensitiveValue in _sensitiveVisibleTextValues) {
          expect(
            visibleText,
            isNot(contains(sensitiveValue)),
            reason: '$preset leaked $sensitiveValue',
          );
        }
      }
    }
  });

  test('share presets never expose raw coordinates', () {
    for (final preset in ShareCardPreset.values) {
      // Given: private telemetry contains raw sample, start/end, and route-node
      // coordinates with distinct sentinel values.
      final content = buildRunShareCardContent(
        preset: preset,
        summary: _summary(),
        detail: _detail(),
      );

      // When: visible share text is gathered for the preset.
      final visibleText = content.visibleText.join(' | ');

      // Then: no preset exposes raw coordinate sentinels.
      for (final coordinate in _coordinateSentinels) {
        expect(
          visibleText,
          isNot(contains(coordinate)),
          reason: '$preset leaked raw coordinate $coordinate',
        );
      }
    }
  });
}

const _coordinateSentinels = [
  '45.123456',
  '-73.123456',
  '45.654321',
  '-73.654321',
  '46.111111',
  '-74.111111',
  '47.222222',
  '-75.222222',
];

const _obdRouteTitleVariants = [
  'OBD Dyno Loop',
  'OBD-II Dyno Loop',
  'OBD2 Dyno Loop',
  'OBDII Dyno Loop',
];

const _sensitiveVisibleTextValues = [
  '214.6',
  '214.60',
  '215',
  'max speed',
  'Max speed',
  'MAX SPEED',
  'OBD2',
  'OBDII',
  'OBD',
  'OBD-II',
  'RPM',
  'throttle',
  'engine load',
  'boost',
  ..._coordinateSentinels,
];

RunSummary _summary({String routeName = 'OBD-II Dyno Loop'}) {
  return RunSummary(
    id: 'run-private',
    date: DateTime.parse('2026-06-30T12:34:56Z'),
    distanceKm: 12.3,
    durationSeconds: 754,
    maxSpeedKmh: 214.6,
    avgSpeedKmh: 58.4,
    routeName: routeName,
    routeId: 'route-private',
    weatherEmoji: 'sunny',
    tempDisplay: '22 C',
    maxLateralG: 0.71,
    maxLongitudinalG: -0.66,
    sharpCornersCount: 4,
    telemetrySampleCount: 2,
    windingSeconds: 330,
    sportSeconds: 120,
    routeDistanceKm: 13.0,
    routeCompletionPct: 95,
    startPoint: const LatLng(45.123456, -73.123456),
    endPoint: const LatLng(45.654321, -73.654321),
  );
}

RunTelemetryDetail _detail() {
  return RunTelemetryDetail(
    runId: 'run-private',
    version: RunTelemetryDetail.currentVersion,
    routeSnapshot: const {
      'name': 'RPM Valley',
      'nodes': [
        {'lat': 46.111111, 'lng': -74.111111},
        {'lat': 47.222222, 'lng': -75.222222},
      ],
    },
    samples: const [
      TelemetrySample(
        tMs: 0,
        lat: 45.123456,
        lng: -73.123456,
        speedKmh: 214.6,
        lateralG: 0.2,
        longitudinalG: 0.1,
        driveMode: 'sport',
      ),
      TelemetrySample(
        tMs: 1000,
        lat: 45.654321,
        lng: -73.654321,
        speedKmh: 120,
        lateralG: 0.3,
        longitudinalG: -0.2,
        driveMode: 'cruise',
      ),
    ],
    sharpEvents: const [
      {
        'lat': 45.123456,
        'lng': -73.123456,
        'lateralG': 0.7,
        'label': 'engine load',
      },
    ],
    analytics: const {
      'maxSpeedKmh': 214.6,
      'obdRpm': 7200,
      'throttle': 91,
      'boost': 14,
    },
    driveModeSeconds: const {'sport': 120},
    weather: const {'description': 'clear'},
    createdAt: DateTime(2026, 6, 30, 12, 40),
  );
}

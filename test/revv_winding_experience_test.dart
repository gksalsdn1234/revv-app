import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/models/run_session.dart';
import 'package:revv_app/models/run_telemetry_detail.dart';
import 'package:revv_app/ui/run_report_metrics.dart';
import 'package:revv_app/ui/winding_experience.dart';

void main() {
  test('ranks fun winding routes ahead of interrupted connectors', () {
    final routes = [
      _route(
        id: 'connector',
        name: 'Busy connector',
        distanceKm: 13,
        tightCurveKm: 0.6,
        mediumCurveKm: 0.9,
        maxContinuousKm: 0.7,
        distanceFromUser: 4,
        stopSignCount: 5,
        trafficSignalCount: 3,
        isConnectorLike: true,
      ),
      _route(
        id: 'sweeper',
        name: 'Forest sweep',
        distanceKm: 24,
        tightCurveKm: 1.1,
        mediumCurveKm: 4.6,
        maxContinuousKm: 3.4,
        distanceFromUser: 17,
        isLoop: true,
        flowScore: 0.72,
      ),
      _route(
        id: 'nearby',
        name: 'Quick local',
        distanceKm: 9,
        tightCurveKm: 0.9,
        mediumCurveKm: 1.2,
        maxContinuousKm: 1.8,
        distanceFromUser: 3,
        flowScore: 0.48,
      ),
    ];

    final ranked = rankWindingRoutes(routes);

    expect(ranked.first.route.id, 'sweeper');
    expect(ranked.first.profile.badges, contains('Loop'));
    expect(ranked.first.profile.metrics.any((m) => m.label == 'Fun'), isTrue);
    expect(ranked.last.route.id, 'connector');
    expect(ranked.last.profile.caution, contains('interruptions'));
  });

  test('report analytics stay finite with empty telemetry samples', () {
    final detail = RunTelemetryDetail.fromSession(
      'empty-run',
      RunSession(
        startTime: DateTime.parse('2026-06-24T10:00:00Z'),
        endTime: DateTime.parse('2026-06-24T10:02:00Z'),
        maxSpeedKmh: 0,
        avgSpeedKmh: 0,
        distanceKm: 0,
        gpsPath: const [],
        weatherEmoji: '',
        tempDisplay: '',
        weatherDesc: '',
      ),
    );

    expect(detail.analytics['sampleCount'], 0);
    expect(detail.analytics['avgAbsLateralG'], 0);
    expect(detail.analytics['p95AbsLateralG'], 0);
    expect(detail.analytics['windingSamplePct'], 0);
  });

  test('route completion is absent for zero-distance route reports', () {
    expect(routeCompletionPercent(drivenKm: 2.4, routeDistanceKm: 0), isNull);
    expect(
      routeCompletionPercent(drivenKm: 2.4, routeDistanceKm: null),
      isNull,
    );
    expect(routeCompletionPercent(drivenKm: 2.4, routeDistanceKm: 3.0), 80);
  });
}

RevvRoute _route({
  required String id,
  required String name,
  required double distanceKm,
  required double tightCurveKm,
  required double mediumCurveKm,
  required double maxContinuousKm,
  required double distanceFromUser,
  double flowScore = 0,
  bool isLoop = false,
  int stopSignCount = 0,
  int trafficSignalCount = 0,
  bool isConnectorLike = false,
}) {
  return RevvRoute(
    id: id,
    name: name,
    nodes: const [LatLng(45.0, -73.0), LatLng(45.1, -73.1)],
    distanceKm: distanceKm,
    windingScore: 4,
    starRating: 3,
    sharpCurveCount: 4,
    centerPoint: const LatLng(45.05, -73.05),
    distanceFromUser: distanceFromUser,
    tightCurveKm: tightCurveKm,
    mediumCurveKm: mediumCurveKm,
    maxContinuousKm: maxContinuousKm,
    flowScore: flowScore,
    isLoop: isLoop,
    stopSignCount: stopSignCount,
    trafficSignalCount: trafficSignalCount,
    isConnectorLike: isConnectorLike,
  );
}

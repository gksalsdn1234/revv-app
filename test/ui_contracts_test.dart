import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/models/run_session.dart';
import 'package:revv_app/ui/ux_contracts.dart';

RevvRoute _route({
  String id = 'route-1',
  String name = '북악 스카이웨이',
  double distanceKm = 28,
  double windingScore = 6.2,
  int sharpCurveCount = 14,
  double distanceFromUser = 12,
}) {
  return RevvRoute(
    id: id,
    name: name,
    nodes: const [LatLng(37.0, 127.0), LatLng(37.1, 127.1)],
    distanceKm: distanceKm,
    windingScore: windingScore,
    starRating: 4,
    sharpCurveCount: sharpCurveCount,
    centerPoint: const LatLng(37.05, 127.05),
    distanceFromUser: distanceFromUser,
  );
}

void main() {
  test('resolveCruiseUiState prefers ready_to_start when route is nearby', () {
    expect(
      resolveCruiseUiState(hasSelectedRoute: true, nearRouteStart: true),
      CruiseUiState.readyToStart,
    );
  });

  test('resolveCruiseUiState distinguishes idle and route selected states', () {
    expect(
      resolveCruiseUiState(hasSelectedRoute: false, nearRouteStart: false),
      CruiseUiState.idle,
    );
    expect(
      resolveCruiseUiState(hasSelectedRoute: true, nearRouteStart: false),
      CruiseUiState.routeSelected,
    );
  });

  test('buildRouteRecommendation creates a reason-first summary', () {
    final summary = buildRouteRecommendation(_route());

    expect(summary.title, '북악 스카이웨이');
    expect(summary.reason, contains('와인딩'));
    expect(summary.primaryMetrics, hasLength(3));
    expect(summary.primaryCta, '이 루트로 달리기');
    expect(summary.advancedActions, isNotEmpty);
  });

  test('resolveRunReviewSummary picks route replay as primary action when route exists', () {
    final session = RunSession(
      startTime: DateTime.parse('2026-04-01T10:00:00Z'),
      endTime: DateTime.parse('2026-04-01T10:30:00Z'),
      maxSpeedKmh: 120,
      avgSpeedKmh: 62,
      distanceKm: 28,
      gpsPath: const [LatLng(37.0, 127.0), LatLng(37.1, 127.1)],
      route: _route(),
      weatherEmoji: '🌤',
      tempDisplay: '18°C',
      weatherDesc: 'clear',
      maxLateralG: 0.42,
    );

    final summary = resolveRunReviewSummary(session);

    expect(summary.primaryActionLabel, '같은 루트 다시 보기');
    expect(summary.headline, isNotEmpty);
    expect(summary.topStats, hasLength(3));
  });

  test('resolveRunReviewSummary falls back to history when route is missing', () {
    final session = RunSession(
      startTime: DateTime.parse('2026-04-01T10:00:00Z'),
      endTime: DateTime.parse('2026-04-01T10:12:00Z'),
      maxSpeedKmh: 80,
      avgSpeedKmh: 45,
      distanceKm: 8,
      gpsPath: const [LatLng(37.0, 127.0), LatLng(37.05, 127.05)],
      weatherEmoji: '🌥',
      tempDisplay: '15°C',
      weatherDesc: 'cloudy',
    );

    final summary = resolveRunReviewSummary(session);

    expect(summary.primaryActionLabel, '기록 보기');
  });
}

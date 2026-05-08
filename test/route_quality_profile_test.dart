import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/ui/route_quality_profile.dart';

RevvRoute _route({
  String id = 'route-1',
  String name = 'Route Test',
  double distanceKm = 18,
  double distanceFromUser = 30,
  double tightCurveKm = 0.8,
  double mediumCurveKm = 2.4,
  double maxContinuousKm = 1.6,
  double flowScore = 0,
  double elevationDelta = 0,
  bool isLoop = false,
  bool isMajorRoadLike = false,
  bool isBridgeLike = false,
  bool isPrivateLike = false,
  bool isConnectorLike = false,
  int stopSignCount = 0,
  int trafficSignalCount = 0,
  String routeCharacter = '',
}) {
  return RevvRoute(
    id: id,
    name: name,
    nodes: const [LatLng(45.0, -73.0), LatLng(45.05, -73.04)],
    distanceKm: distanceKm,
    windingScore: 6.4,
    starRating: 4,
    sharpCurveCount: 9,
    centerPoint: const LatLng(45.025, -73.02),
    distanceFromUser: distanceFromUser,
    tightCurveKm: tightCurveKm,
    mediumCurveKm: mediumCurveKm,
    maxContinuousKm: maxContinuousKm,
    flowScore: flowScore,
    elevationDelta: elevationDelta,
    isLoop: isLoop,
    isMajorRoadLike: isMajorRoadLike,
    isBridgeLike: isBridgeLike,
    isPrivateLike: isPrivateLike,
    isConnectorLike: isConnectorLike,
    stopSignCount: stopSignCount,
    trafficSignalCount: trafficSignalCount,
    routeCharacter: routeCharacter,
  );
}

void main() {
  test('classifies primary route types consistently', () {
    expect(RouteQualityProfile.fromRoute(_route(isLoop: true)).typeLabel, '루프');
    expect(
      RouteQualityProfile.fromRoute(
        _route(distanceFromUser: 8, distanceKm: 12),
      ).typeLabel,
      '근처',
    );
    expect(
      RouteQualityProfile.fromRoute(
        _route(tightCurveKm: 2.8, mediumCurveKm: 0.4),
      ).typeLabel,
      '타이트',
    );
    expect(
      RouteQualityProfile.fromRoute(
        _route(tightCurveKm: 0.2, mediumCurveKm: 3.2),
      ).typeLabel,
      '스위퍼',
    );
    expect(
      RouteQualityProfile.fromRoute(
        _route(tightCurveKm: 0.6, mediumCurveKm: 0.8, maxContinuousKm: 2.5),
      ).typeLabel,
      '흐름',
    );
    expect(
      RouteQualityProfile.fromRoute(_route(distanceKm: 32)).typeLabel,
      '긴 루트',
    );
    expect(
      RouteQualityProfile.fromRoute(_route(elevationDelta: 80)).typeLabel,
      '고도 변화',
    );
  });

  test('exposes multi tags for filters without losing the primary label', () {
    final profile = RouteQualityProfile.fromRoute(
      _route(
        distanceFromUser: 10,
        tightCurveKm: 2.4,
        mediumCurveKm: 0.8,
        maxContinuousKm: 2.3,
        isLoop: false,
      ),
    );

    expect(profile.typeLabel, '근처');
    expect(profile.hasTag(RouteQualityTag.nearby), isTrue);
    expect(profile.hasTag(RouteQualityTag.tight), isTrue);
    expect(profile.hasTag(RouteQualityTag.flow), isTrue);
  });

  test('reason, risk, and metrics are data based', () {
    final profile = RouteQualityProfile.fromRoute(
      _route(
        tightCurveKm: 2.1,
        mediumCurveKm: 0.4,
        stopSignCount: 4,
        trafficSignalCount: 3,
      ),
    );

    expect(profile.reasonLabel, contains('타이트'));
    expect(profile.riskLabel, contains('정지 요소 7개'));
    expect(profile.curveDensityLabel, isNotEmpty);
    expect(profile.qualityScore, inInclusiveRange(35, 96));
    expect(profile.quickMetrics.map((metric) => metric.label), contains('커브'));
    expect(profile.quickMetrics.map((metric) => metric.label), contains('흐름'));
  });

  test('road risk takes precedence over generic caution', () {
    expect(
      RouteQualityProfile.fromRoute(_route(isPrivateLike: true)).riskLabel,
      contains('접근 제한'),
    );
    expect(
      RouteQualityProfile.fromRoute(_route(isMajorRoadLike: true)).riskLabel,
      contains('간선도로'),
    );
    expect(
      RouteQualityProfile.fromRoute(_route(isBridgeLike: true)).riskLabel,
      contains('브리지'),
    );
  });
}

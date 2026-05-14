import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/ui/route_difficulty_profile.dart';

RevvRoute _route({
  double distanceKm = 20,
  double tightCurveKm = 0,
  double mediumCurveKm = 0,
  bool isMajorRoadLike = false,
  bool isBridgeLike = false,
  bool isPrivateLike = false,
  bool isConnectorLike = false,
  String? qualityRejectReason,
}) {
  return RevvRoute(
    id: 'route',
    name: 'Route',
    nodes: const [LatLng(45.0, -73.0), LatLng(45.1, -73.1)],
    distanceKm: distanceKm,
    windingScore: 5,
    starRating: 4,
    sharpCurveCount: 10,
    centerPoint: const LatLng(45.05, -73.05),
    distanceFromUser: 12,
    tightCurveKm: tightCurveKm,
    mediumCurveKm: mediumCurveKm,
    isMajorRoadLike: isMajorRoadLike,
    isBridgeLike: isBridgeLike,
    isPrivateLike: isPrivateLike,
    isConnectorLike: isConnectorLike,
    qualityRejectReason: qualityRejectReason,
  );
}

void main() {
  test('classifies gentle winding and tight display colors', () {
    expect(
      RouteDifficultyProfile.fromRoute(_route(mediumCurveKm: 2.4)).difficulty,
      RouteDifficultyLevel.gentle,
    );
    expect(
      RouteDifficultyProfile.fromRoute(
        _route(tightCurveKm: 1.2, mediumCurveKm: 6.0),
      ).difficulty,
      RouteDifficultyLevel.winding,
    );
    expect(
      RouteDifficultyProfile.fromRoute(
        _route(tightCurveKm: 6.8, mediumCurveKm: 3.0),
      ).difficulty,
      RouteDifficultyLevel.tight,
    );
  });

  test('hard risk routes are muted for map display', () {
    final private = RouteDifficultyProfile.fromRoute(
      _route(tightCurveKm: 5, isPrivateLike: true),
    );
    final rejected = RouteDifficultyProfile.fromRoute(
      _route(tightCurveKm: 5, qualityRejectReason: 'facility'),
    );

    expect(private.difficulty, RouteDifficultyLevel.muted);
    expect(rejected.difficulty, RouteDifficultyLevel.muted);
    expect(private.opacity, lessThan(0.3));
  });

  test('soft road risk keeps color but lowers emphasis', () {
    final clean = RouteDifficultyProfile.fromRoute(
      _route(tightCurveKm: 6.8, mediumCurveKm: 3.0),
    );
    final major = RouteDifficultyProfile.fromRoute(
      _route(tightCurveKm: 6.8, mediumCurveKm: 3.0, isMajorRoadLike: true),
    );

    expect(major.difficulty, RouteDifficultyLevel.tight);
    expect(major.opacity, lessThan(clean.opacity));
  });
}

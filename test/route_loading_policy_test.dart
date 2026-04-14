import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/services/route_loading_policy.dart';

RevvRoute _route({
  required String id,
  required double distanceKm,
  required double windingScore,
  double distanceFromUser = 10,
  double lat = 37.0,
  double lng = 127.0,
}) {
  return RevvRoute(
    id: id,
    name: 'route-$id',
    nodes: [LatLng(lat, lng), LatLng(lat + 0.1, lng + 0.1)],
    distanceKm: distanceKm,
    windingScore: windingScore,
    starRating: 4,
    sharpCurveCount: 10,
    centerPoint: LatLng(lat + 0.05, lng + 0.05),
    distanceFromUser: distanceFromUser,
  );
}

void main() {
  test('initial overpass query skips primary roads by default', () {
    final query = buildOverpassQuery(
      lat: 37.5,
      lng: 127.0,
      radiusM: 50000,
      includePrimary: false,
    );

    expect(query, isNot(contains('"highway"="primary"')));
    expect(query, contains('"highway"="secondary"'));
    expect(query, contains('[timeout:12]'));
  });

  test('expanded overpass query can include primary roads', () {
    final query = buildOverpassQuery(
      lat: 37.5,
      lng: 127.0,
      radiusM: 50000,
      includePrimary: true,
    );

    expect(query, contains('"highway"="primary"'));
  });

  test('relaxed overpass query can omit name filter', () {
    final query = buildOverpassQuery(
      lat: 45.5,
      lng: -73.6,
      radiusM: 30000,
      includePrimary: true,
      requireName: false,
    );

    expect(query, contains('way["highway"="primary"](around:30000'));
    expect(query, isNot(contains('"highway"="secondary"]["name"]')));
  });

  test('preferred overpass endpoints are capped to fast shortlist', () {
    expect(preferredOverpassEndpoints.length, lessThanOrEqualTo(3));
    expect(preferredOverpassEndpoints, contains('https://overpass-api.de/api/interpreter'));
  });

  test('mergeDiversityRoutes keeps existing selection and only adds distinct routes', () {
    final existing = [
      _route(id: 'a', distanceKm: 12, windingScore: 4.0, lat: 37.0, lng: 127.0),
      _route(id: 'b', distanceKm: 20, windingScore: 5.0, lat: 37.2, lng: 127.2),
    ];
    final incoming = [
      _route(id: 'b-new', distanceKm: 20.1, windingScore: 5.2, lat: 37.21, lng: 127.21),
      _route(id: 'c', distanceKm: 30, windingScore: 6.5, lat: 38.0, lng: 128.0),
    ];

    final merged = mergeDiversityRoutes(existing, incoming, limit: 25);

    expect(merged.any((r) => r.id == 'a'), isTrue);
    expect(merged.any((r) => r.id == 'c'), isTrue);
    expect(merged.length, 3);
  });

  test('cached routes are reused only when cache center stays near current location', () {
    expect(
      shouldUseCachedRoutes(
        cacheCenter: const LatLng(37.50, 127.00),
        targetCenter: const LatLng(37.56, 127.04),
        searchRadiusKm: 50,
      ),
      isTrue,
    );

    expect(
      shouldUseCachedRoutes(
        cacheCenter: const LatLng(40.7128, -74.0060),
        targetCenter: const LatLng(37.5665, 126.9780),
        searchRadiusKm: 50,
      ),
      isFalse,
    );
  });

  test('empty overpass payload is treated as suspicious', () {
    expect(
      looksLikeEmptyOverpassPayload('{"version":0.6,"elements":[]}'),
      isTrue,
    );
    expect(
      looksLikeEmptyOverpassPayload('{"version":0.6,"elements":[{"type":"way"}]}'),
      isFalse,
    );
  });

  test('search radius plan expands in two balanced steps', () {
    expect(buildSearchRadiusPlan(30), [30, 50, 80]);
    expect(buildSearchRadiusPlan(50), [50, 70, 100]);
  });

  test('balanced thresholds are more permissive than strict thresholds', () {
    final strict = thresholdsForStage(RouteSearchStage.strict);
    final balanced = thresholdsForStage(RouteSearchStage.balanced);
    final expanded = thresholdsForStage(RouteSearchStage.expanded);

    expect(balanced.minCurvyDistanceKm, lessThan(strict.minCurvyDistanceKm));
    expect(balanced.maxContinuousKmMin, lessThan(strict.maxContinuousKmMin));
    expect(balanced.maxStraightRunKmMax, greaterThanOrEqualTo(strict.maxStraightRunKmMax));
    expect(balanced.maxStraightFractionMax, greaterThan(strict.maxStraightFractionMax));
    expect(balanced.maxSignalPerKm, greaterThan(strict.maxSignalPerKm));
    expect(expanded.maxIntersectionPerKm, greaterThan(strict.maxIntersectionPerKm));
    expect(balanced.curvyFractionMin, lessThan(strict.curvyFractionMin));
    expect(expanded.dedupDistanceKm, lessThan(strict.dedupDistanceKm));
    expect(expanded.maxSelectedRoutes, greaterThanOrEqualTo(balanced.maxSelectedRoutes));
  });

  test('mergeDiversityRoutes can relax dedupe distance for low-density regions', () {
    final existing = [
      _route(id: 'a', distanceKm: 12, windingScore: 4.0, lat: 45.0, lng: -73.0),
    ];
    final incoming = [
      _route(id: 'b', distanceKm: 18, windingScore: 4.6, lat: 45.035, lng: -73.035),
    ];

    final strictMerged = mergeDiversityRoutes(
      existing,
      incoming,
      limit: 25,
      dedupeDistanceKm: 6.0,
    );
    final relaxedMerged = mergeDiversityRoutes(
      existing,
      incoming,
      limit: 25,
      dedupeDistanceKm: 4.0,
    );

    expect(strictMerged.length, 1);
    expect(relaxedMerged.length, 2);
  });

  test('straight dominant routes are rejected even in expanded mode', () {
    final expanded = thresholdsForStage(RouteSearchStage.expanded);

    expect(
      isStraightDominantRoute(
        distanceKm: 18,
        curvyDistanceKm: 1.1,
        maxStraightRunKm: 6.5,
        thresholds: expanded,
      ),
      isTrue,
    );
  });

  test('balanced mode keeps moderately curvy routes eligible', () {
    final balanced = thresholdsForStage(RouteSearchStage.balanced);

    expect(
      isStraightDominantRoute(
        distanceKm: 20,
        curvyDistanceKm: 4.3,
        maxStraightRunKm: 4.2,
        thresholds: balanced,
      ),
      isFalse,
    );
  });

  test('non-strict stages can reuse narrower search payloads', () {
    expect(
      canReuseSearchResponse(
        stage: RouteSearchStage.expanded,
        cachedRadiusM: 50000,
        requestedRadiusM: 70000,
      ),
      isTrue,
    );

    expect(
      canReuseSearchResponse(
        stage: RouteSearchStage.strict,
        cachedRadiusM: 50000,
        requestedRadiusM: 70000,
      ),
      isFalse,
    );
  });

  test('composite fallback can create an extra winding route from nearby candidates', () {
    final routes = [
      RevvRoute(
        id: 'a',
        name: 'North Twist',
        nodes: [const LatLng(45.00, -73.00), const LatLng(45.04, -73.04)],
        distanceKm: 9,
        windingScore: 6.6,
        starRating: 4,
        sharpCurveCount: 8,
        centerPoint: const LatLng(45.02, -73.02),
        distanceFromUser: 12,
        tightCurveKm: 1.8,
        mediumCurveKm: 1.9,
        maxContinuousKm: 1.4,
      ),
      RevvRoute(
        id: 'b',
        name: 'Valley Sweep',
        nodes: [const LatLng(45.05, -73.05), const LatLng(45.09, -73.08)],
        distanceKm: 10,
        windingScore: 6.1,
        starRating: 4,
        sharpCurveCount: 7,
        centerPoint: const LatLng(45.07, -73.065),
        distanceFromUser: 15,
        tightCurveKm: 1.2,
        mediumCurveKm: 2.8,
        maxContinuousKm: 1.3,
      ),
    ];

    final result = buildCompositeFallbackRoutes(routes, targetCount: 3);

    expect(result.length, 3);
    expect(result.last.id, startsWith('combo:'));
    expect(result.last.distanceKm, greaterThan(19));
  });

  test('composite fallback skips straight or distant pairings', () {
    final routes = [
      RevvRoute(
        id: 'a',
        name: 'Near Twist',
        nodes: [const LatLng(45.00, -73.00), const LatLng(45.04, -73.04)],
        distanceKm: 9,
        windingScore: 6.2,
        starRating: 4,
        sharpCurveCount: 8,
        centerPoint: const LatLng(45.02, -73.02),
        distanceFromUser: 12,
        tightCurveKm: 0.2,
        mediumCurveKm: 0.5,
        maxContinuousKm: 0.8,
      ),
      RevvRoute(
        id: 'b',
        name: 'Far Straight',
        nodes: [const LatLng(45.30, -73.30), const LatLng(45.38, -73.38)],
        distanceKm: 12,
        windingScore: 4.2,
        starRating: 3,
        sharpCurveCount: 2,
        centerPoint: const LatLng(45.34, -73.34),
        distanceFromUser: 30,
        tightCurveKm: 0.2,
        mediumCurveKm: 0.5,
        maxContinuousKm: 0.8,
      ),
    ];

    final result = buildCompositeFallbackRoutes(routes, targetCount: 3);

    expect(result.length, 2);
  });

  test('routes need a compelling reason tag to be explainable', () {
    final compelling = RevvRoute(
      id: 'good',
      name: 'North Ridge',
      nodes: [const LatLng(45.0, -73.0), const LatLng(45.05, -73.05)],
      distanceKm: 14,
      windingScore: 6.4,
      starRating: 4,
      sharpCurveCount: 8,
      centerPoint: const LatLng(45.025, -73.025),
      distanceFromUser: 14,
      tightCurveKm: 1.8,
      mediumCurveKm: 2.6,
      maxContinuousKm: 1.4,
    );
    final weak = RevvRoute(
      id: 'weak',
      name: 'Flat Connector',
      nodes: [const LatLng(45.0, -73.0), const LatLng(45.08, -73.08)],
      distanceKm: 18,
      windingScore: 3.4,
      starRating: 2,
      sharpCurveCount: 1,
      centerPoint: const LatLng(45.04, -73.04),
      distanceFromUser: 20,
      tightCurveKm: 0.3,
      mediumCurveKm: 0.8,
      maxContinuousKm: 0.6,
    );

    expect(hasCompellingRouteReason(compelling), isTrue);
    expect(primaryRouteReason(compelling), isNotNull);
    expect(hasCompellingRouteReason(weak), isFalse);
    expect(primaryRouteReason(weak), isNull);
  });

  test('facility-like names are rejected as low quality driving routes', () {
    final route = RevvRoute(
      id: 'kart',
      name: 'Karting',
      nodes: [const LatLng(45.0, -73.0), const LatLng(45.01, -73.01)],
      distanceKm: 4.2,
      windingScore: 8.5,
      starRating: 5,
      sharpCurveCount: 14,
      centerPoint: const LatLng(45.005, -73.005),
      distanceFromUser: 8,
      tightCurveKm: 1.7,
      mediumCurveKm: 1.1,
      maxContinuousKm: 0.6,
      isLoop: true,
    );

    expect(hasFacilityLikeName(route.name), isTrue);
    expect(shouldRejectLowQualityRoute(route), isTrue);
  });

  test('numeric-only short routes are rejected', () {
    final route = RevvRoute(
      id: 'num',
      name: '1117718105',
      nodes: [const LatLng(45.46, -73.62), const LatLng(45.47, -73.63)],
      distanceKm: 6.8,
      windingScore: 6.2,
      starRating: 4,
      sharpCurveCount: 8,
      centerPoint: const LatLng(45.465, -73.625),
      distanceFromUser: 5,
      tightCurveKm: 1.0,
      mediumCurveKm: 1.1,
      maxContinuousKm: 0.8,
      isLoop: false,
    );

    expect(hasNumericOnlyName(route.name), isTrue);
    expect(shouldRejectLowQualityRoute(route), isTrue);
  });

  test('compact loop facilities are rejected even with high winding score', () {
    final route = RevvRoute(
      id: 'compact',
      name: 'North Mini Loop',
      nodes: const [
        LatLng(45.0000, -73.0000),
        LatLng(45.0020, -73.0020),
        LatLng(45.0040, -73.0005),
        LatLng(45.0020, -72.9980),
        LatLng(45.0000, -73.0000),
      ],
      distanceKm: 5.5,
      windingScore: 7.4,
      starRating: 5,
      sharpCurveCount: 13,
      centerPoint: const LatLng(45.0020, -73.0000),
      distanceFromUser: 9,
      tightCurveKm: 1.6,
      mediumCurveKm: 1.0,
      maxContinuousKm: 0.7,
      isLoop: true,
    );

    expect(routeFootprintDiagonalKm(route), lessThan(1.35));
    expect(isCompactFacilityLikeRoute(route), isTrue);
    expect(shouldRejectLowQualityRoute(route), isTrue);
  });

  test('driveability multiplier penalizes low-confidence numeric routes', () {
    final weak = RevvRoute(
      id: 'weak-num',
      name: '1247366610',
      nodes: [const LatLng(45.0, -73.0), const LatLng(45.04, -73.04)],
      distanceKm: 8.5,
      windingScore: 6.0,
      starRating: 4,
      sharpCurveCount: 6,
      centerPoint: const LatLng(45.02, -73.02),
      distanceFromUser: 10,
      tightCurveKm: 0.8,
      mediumCurveKm: 0.9,
      maxContinuousKm: 0.6,
      isLoop: false,
    );
    final good = RevvRoute(
      id: 'good-road',
      name: 'Belvedere Road',
      nodes: [const LatLng(45.0, -73.0), const LatLng(45.08, -73.05)],
      distanceKm: 14.0,
      windingScore: 6.0,
      starRating: 4,
      sharpCurveCount: 9,
      centerPoint: const LatLng(45.04, -73.025),
      distanceFromUser: 10,
      tightCurveKm: 1.2,
      mediumCurveKm: 2.1,
      maxContinuousKm: 1.3,
      isLoop: false,
    );

    expect(routeDriveabilityMultiplier(weak), lessThan(0.7));
    expect(routeDriveabilityMultiplier(good), greaterThan(0.9));
  });

  test('quality guardrails keep named fallback routes when compelling reasons are absent', () {
    final routes = [
      RevvRoute(
        id: 'named-1',
        name: 'Rue des Galets',
        nodes: [const LatLng(45.50, -73.60), const LatLng(45.56, -73.54)],
        distanceKm: 10.5,
        windingScore: 5.4,
        starRating: 3,
        sharpCurveCount: 3,
        centerPoint: const LatLng(45.53, -73.57),
        distanceFromUser: 11,
        tightCurveKm: 0.5,
        mediumCurveKm: 0.6,
        maxContinuousKm: 0.4,
      ),
      RevvRoute(
        id: 'named-2',
        name: 'Belvedere Road',
        nodes: [const LatLng(45.48, -73.62), const LatLng(45.55, -73.57)],
        distanceKm: 11.2,
        windingScore: 5.1,
        starRating: 3,
        sharpCurveCount: 4,
        centerPoint: const LatLng(45.515, -73.595),
        distanceFromUser: 14,
        tightCurveKm: 0.4,
        mediumCurveKm: 0.7,
        maxContinuousKm: 0.45,
      ),
      RevvRoute(
        id: 'numeric',
        name: '1216833929',
        nodes: [const LatLng(45.46, -73.64), const LatLng(45.50, -73.61)],
        distanceKm: 9.4,
        windingScore: 5.7,
        starRating: 3,
        sharpCurveCount: 5,
        centerPoint: const LatLng(45.48, -73.625),
        distanceFromUser: 13,
        tightCurveKm: 0.7,
        mediumCurveKm: 0.7,
        maxContinuousKm: 0.4,
      ),
    ];

    final filtered = applyQualityGuardrails(routes);

    expect(filtered.map((route) => route.id), containsAll(['named-1', 'named-2']));
    expect(filtered.any((route) => route.id == 'numeric'), isFalse);
  });

  test('supabase candidate filter removes tiny segment rows before ranking', () {
    final routes = [
      RevvRoute(
        id: 'kart',
        name: 'Karting',
        nodes: [const LatLng(45.40, -73.60), const LatLng(45.401, -73.601)],
        distanceKm: 0.3,
        windingScore: 1700,
        starRating: 5,
        sharpCurveCount: 12,
        centerPoint: const LatLng(45.4005, -73.6005),
        distanceFromUser: 20,
      ),
      RevvRoute(
        id: 'numeric',
        name: '1216833929',
        nodes: [const LatLng(45.41, -73.61), const LatLng(45.412, -73.612)],
        distanceKm: 0.6,
        windingScore: 1500,
        starRating: 5,
        sharpCurveCount: 10,
        centerPoint: const LatLng(45.411, -73.611),
        distanceFromUser: 18,
      ),
      RevvRoute(
        id: 'named-road',
        name: 'Chemin de la Petite-Cote',
        nodes: [const LatLng(45.42, -73.62), const LatLng(45.50, -73.54)],
        distanceKm: 11.9,
        windingScore: 459,
        starRating: 4,
        sharpCurveCount: 18,
        centerPoint: const LatLng(45.46, -73.58),
        distanceFromUser: 25,
      ),
    ];

    final filtered = filterSupabaseRouteCandidates(routes);

    expect(filtered.map((route) => route.id), ['named-road']);
  });

  test('quality guardrails prefer keep candidates over major-road-like routes when enough exist', () {
    RevvRoute keepRoute(String id, String name) => RevvRoute(
          id: id,
          name: name,
          nodes: [const LatLng(45.40, -73.60), const LatLng(45.48, -73.52)],
          distanceKm: 11.0,
          windingScore: 5.9,
          starRating: 4,
          sharpCurveCount: 5,
          centerPoint: const LatLng(45.44, -73.56),
          distanceFromUser: 20,
          tightCurveKm: 0.7,
          mediumCurveKm: 0.8,
          maxContinuousKm: 0.5,
        );
    RevvRoute maybeRoute(String id, String name) => RevvRoute(
          id: id,
          name: name,
          nodes: [const LatLng(45.42, -73.60), const LatLng(45.50, -73.54)],
          distanceKm: 12.0,
          windingScore: 6.4,
          starRating: 4,
          sharpCurveCount: 6,
          centerPoint: const LatLng(45.46, -73.57),
          distanceFromUser: 18,
          tightCurveKm: 0.8,
          mediumCurveKm: 0.9,
          maxContinuousKm: 0.6,
          isMajorRoadLike: true,
        );

    final routes = [
      keepRoute('keep-1', 'Chemin de la Petite-Cote'),
      keepRoute('keep-2', 'Chemin du Fleuve'),
      keepRoute('keep-3', 'Rue Main'),
      keepRoute('keep-4', 'Chemin Saint-Charles'),
      keepRoute('keep-5', 'Rang de la Riviere Nord'),
      keepRoute('keep-6', 'Chemin de la Grande-Cote'),
      keepRoute('keep-7', 'Montee Morel'),
      keepRoute('keep-8', 'Rang Saint-Marc'),
      maybeRoute('maybe-1', 'Boulevard Perrot'),
      maybeRoute('maybe-2', 'Boulevard Gouin Ouest'),
    ];

    final filtered = applyQualityGuardrails(routes);

    expect(filtered.length, 8);
    expect(filtered.every((route) => !isMajorRoadLikeRouteName(route.name)), isTrue);
  });

  test('recommendationScore prefers flow-aware score fields when present', () {
    final route = RevvRoute(
      id: 'scored',
      name: 'North Ridge',
      nodes: [const LatLng(45.0, -73.0), const LatLng(45.08, -73.05)],
      distanceKm: 14.0,
      windingScore: 6.0,
      starRating: 4,
      sharpCurveCount: 9,
      centerPoint: const LatLng(45.04, -73.025),
      distanceFromUser: 10,
      routeRankScore: 7.7,
      funScore: 8.3,
      flowScore: 0.81,
      driveabilityPenalty: 0.92,
      stopSignCount: 2,
      trafficSignalCount: 0,
      stopControlDensity: 0.14,
      roadClassBucket: 'rural_named',
      isNamed: true,
    );

    expect(recommendationScore(route), 7.7);
    expect(recommendationTier(route), 'keep');
  });

  test('hard reject recommendation catches stop-heavy short routes', () {
    final route = RevvRoute(
      id: 'stop-heavy',
      name: 'Rue Saint Example',
      nodes: [const LatLng(45.0, -73.0), const LatLng(45.04, -73.04)],
      distanceKm: 8.0,
      windingScore: 5.2,
      starRating: 3,
      sharpCurveCount: 4,
      centerPoint: const LatLng(45.02, -73.02),
      distanceFromUser: 9,
      stopSignCount: 5,
      trafficSignalCount: 1,
      stopControlDensity: 0.85,
      flowScore: 0.22,
      isNamed: true,
    );

    expect(isHardRejectedRecommendation(route), isTrue);
    expect(recommendationTier(route), 'reject');
  });
}

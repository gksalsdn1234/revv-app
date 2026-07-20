import 'dart:math' as math;

import '../core/app_language.dart';
import '../models/revv_route.dart';

const targetVisibleRoutes = 12;
const minimumVisibleRoutes = 6;
const defaultVisibleRoutes = 16;
const maximumVisibleRoutes = 30;

final _facilityNamePattern = RegExp(
  r'\b(kart|karting|drift|circuit|raceway|speedway|motorsport|autocross|pit\s?lane|paddock|test\s?track|trackday)\b',
  caseSensitive: false,
);
final _bridgeNamePattern = RegExp(
  r'\b(pont|bridge|viaduct|causeway)\b',
  caseSensitive: false,
);
final _connectorNamePattern = RegExp(
  r'\b(sortie|exit|ramp|bretelle|interchange|junction|connector)\b',
  caseSensitive: false,
);
final _majorRoadNamePattern = RegExp(
  r'\b(boulevard|autoroute|highway)\b',
  caseSensitive: false,
);
final _numericOnlyRouteNamePattern = RegExp(r'^[\d\-\s_]+$');

enum RouteSearchStage { strict, balanced, expanded }

enum RouteFilterStrength { precise, balanced, broad }

enum DriveBudget { any, short, medium, long }

const routeCoverageRadiusKm = 150.0;
const routeOverviewZoomThreshold = 9.5;
const routeCoverageCenters = <LatLng>[
  LatLng(45.5017, -73.5673), // Montreal
  LatLng(46.8139, -71.2080), // Quebec City
  LatLng(43.6532, -79.3832), // Toronto
  LatLng(49.2827, -123.1207), // Vancouver
  LatLng(51.0447, -114.0719), // Calgary
];

const routeOverviewCenters = <LatLng>[
  LatLng(49.2827, -123.1207), // Vancouver
  LatLng(49.8880, -119.4960), // Kelowna
  LatLng(53.9171, -122.7497), // Prince George
  LatLng(51.0447, -114.0719), // Calgary
  LatLng(49.6956, -112.8451), // Lethbridge
  LatLng(53.5461, -113.4938), // Edmonton
  LatLng(50.4452, -104.6189), // Regina
  LatLng(52.1332, -106.6700), // Saskatoon
  LatLng(49.8951, -97.1384), // Winnipeg
  LatLng(49.8485, -99.9501), // Brandon
  LatLng(48.3809, -89.2477), // Thunder Bay
  LatLng(46.5136, -84.3358), // Sault Ste. Marie
  LatLng(46.4917, -80.9930), // Sudbury
  LatLng(43.6532, -79.3832), // Toronto
  LatLng(45.4215, -75.6972), // Ottawa
  LatLng(45.5017, -73.5673), // Montreal
  LatLng(46.8139, -71.2080), // Quebec City
  LatLng(45.9636, -66.6431), // Fredericton
  LatLng(44.6488, -63.5752), // Halifax
  LatLng(47.5615, -52.7126), // St. John's
  LatLng(60.7212, -135.0568), // Whitehorse
];

bool isRouteOverviewZoom(double zoom) => zoom <= routeOverviewZoomThreshold;

List<RevvRoute> mergeRouteOverviewFields(
  Iterable<List<RevvRoute>> fields, {
  required int limit,
}) {
  final sources = fields.where((field) => field.isNotEmpty).toList();
  final indexes = List<int>.filled(sources.length, 0);
  final seen = <String>{};
  final merged = <RevvRoute>[];

  while (merged.length < limit) {
    var addedInRound = false;
    for (
      var sourceIndex = 0;
      sourceIndex < sources.length && merged.length < limit;
      sourceIndex++
    ) {
      final source = sources[sourceIndex];
      while (indexes[sourceIndex] < source.length) {
        final route = source[indexes[sourceIndex]++];
        if (!seen.add(route.id)) continue;
        merged.add(route);
        addedInRound = true;
        break;
      }
    }
    if (!addedInRound) break;
  }

  return List<RevvRoute>.unmodifiable(merged);
}

class RegionRequestGrid {
  final double latRounded;
  final double lngRounded;

  const RegionRequestGrid({required this.latRounded, required this.lngRounded});

  String get gridKey =>
      '${latRounded.toStringAsFixed(1)},${lngRounded.toStringAsFixed(1)}';
}

/// 지역별 출시 경계를 두지 않는다. 지도에서 이동한 모든 위치를 조회한다.
const bool routeCoverageOpenAll = true;

bool isPointInsideRouteCoverage(
  LatLng point, {
  Iterable<LatLng> centers = routeCoverageCenters,
  double radiusKm = routeCoverageRadiusKm,
  bool openAll = routeCoverageOpenAll,
}) {
  if (openAll) return true;
  return centers.any(
    (center) => RevvRoute.haversineKm(point, center) <= radiusKm,
  );
}

RegionRequestGrid regionRequestGridFor(LatLng point) {
  return RegionRequestGrid(
    latRounded: _roundToTenth(point.lat),
    lngRounded: _roundToTenth(point.lng),
  );
}

double _roundToTenth(double value) {
  return (value * 10).roundToDouble() / 10;
}

RouteFilterStrength routeFilterStrengthFromStorage(String? value) {
  return switch (value) {
    'precise' => RouteFilterStrength.precise,
    'broad' => RouteFilterStrength.broad,
    _ => RouteFilterStrength.balanced,
  };
}

String routeFilterStrengthStorageValue(RouteFilterStrength strength) {
  return switch (strength) {
    RouteFilterStrength.precise => 'precise',
    RouteFilterStrength.balanced => 'balanced',
    RouteFilterStrength.broad => 'broad',
  };
}

String routeFilterStrengthLabel(RouteFilterStrength strength) {
  return switch (strength) {
    RouteFilterStrength.precise => '정밀',
    RouteFilterStrength.balanced => '균형',
    RouteFilterStrength.broad => '넓게',
  };
}

String routeFilterStrengthDescription(RouteFilterStrength strength) {
  return switch (strength) {
    RouteFilterStrength.precise => '품질 높은 와인딩 후보만 봅니다.',
    RouteFilterStrength.balanced => '품질과 후보 수를 균형 있게 봅니다.',
    RouteFilterStrength.broad => '안전 최저선은 유지하고 더 다양한 후보를 봅니다.',
  };
}

int estimatedDriveMinutes(RevvRoute route) {
  // Touring estimate for route planning only: base minutes come from distance,
  // then denser bends and stop controls add conservative buffer time. No
  // target pace is shown to the user; UI surfaces minutes only.
  const minutesPerKm = 1.25;
  const maxWindingBuffer = 0.28;
  const stopSignBufferMin = 0.75;
  const signalBufferMin = 1.10;
  final curvyKm = route.tightCurveKm + route.mediumCurveKm;
  final windingDensity = route.distanceKm <= 0
      ? 0.0
      : (curvyKm / route.distanceKm).clamp(0.0, 1.0);
  final baseMinutes = route.distanceKm * minutesPerKm;
  final windingBuffer = baseMinutes * windingDensity * maxWindingBuffer;
  final stopBuffer =
      route.stopSignCount * stopSignBufferMin +
      route.trafficSignalCount * signalBufferMin;
  return math.max(1, (baseMinutes + windingBuffer + stopBuffer).round());
}

bool driveBudgetMatches(RevvRoute route, DriveBudget budget) {
  return driveBudgetMatchesMinutes(estimatedDriveMinutes(route), budget);
}

bool driveBudgetMatchesMinutes(int minutes, DriveBudget budget) {
  return switch (budget) {
    DriveBudget.any => true,
    DriveBudget.short => minutes >= 15 && minutes <= 45,
    DriveBudget.medium => minutes >= 45 && minutes <= 90,
    DriveBudget.long => minutes >= 90,
  };
}

class RouteFilterThresholds {
  final double minLoopDistanceKm;
  final double minLinearDistanceKm;
  final int signalHardLimit;
  final double totalCurvatureMin;
  final double minCurvyDistanceKm;
  final double maxContinuousKmMin;
  final double maxStraightRunKmMax;
  final double maxStraightFractionMax;
  final double maxSignalPerKm;
  final double maxIntersectionPerKm;
  final double curvyFractionMin;
  final double curvatureDensityMin;
  final double spreadRatioMin;
  final double elongatedAspectMin;
  final double elongatedCurvyFractionMin;
  final double dedupDistanceKm;
  final int maxSelectedRoutes;

  const RouteFilterThresholds({
    required this.minLoopDistanceKm,
    required this.minLinearDistanceKm,
    required this.signalHardLimit,
    required this.totalCurvatureMin,
    required this.minCurvyDistanceKm,
    required this.maxContinuousKmMin,
    required this.maxStraightRunKmMax,
    required this.maxStraightFractionMax,
    required this.maxSignalPerKm,
    required this.maxIntersectionPerKm,
    required this.curvyFractionMin,
    required this.curvatureDensityMin,
    required this.spreadRatioMin,
    required this.elongatedAspectMin,
    required this.elongatedCurvyFractionMin,
    required this.dedupDistanceKm,
    required this.maxSelectedRoutes,
  });
}

const preferredOverpassEndpoints = <String>[
  'https://overpass-api.de/api/interpreter',
  'https://overpass.kumi.systems/api/interpreter',
  'https://overpass.osm.ch/api/interpreter',
];

String buildOverpassQuery({
  required double lat,
  required double lng,
  required int radiusM,
  bool includePrimary = false,
  bool requireName = true,
  int timeoutSeconds = 12,
}) {
  String wayClause(String highway) {
    final nameFilter = requireName ? '["name"]' : '';
    return '  way["highway"="$highway"]$nameFilter(around:$radiusM,$lat,$lng);';
  }

  final ways = <String>[
    if (includePrimary) wayClause('primary'),
    wayClause('secondary'),
    wayClause('tertiary'),
    wayClause('unclassified'),
    '  node["highway"="traffic_signals"](around:$radiusM,$lat,$lng);',
    '  node["highway"="stop"](around:$radiusM,$lat,$lng);',
  ];

  return '''
[out:json][timeout:$timeoutSeconds];
(
${ways.join('\n')}
);
out geom qt;
''';
}

List<RevvRoute> mergeDiversityRoutes(
  List<RevvRoute> existing,
  List<RevvRoute> incoming, {
  int limit = 25,
  double dedupeDistanceKm = 6.0,
}) {
  final pool = List<RevvRoute>.from(existing);
  for (final route in incoming) {
    final isNearDuplicate = pool.any(
      (current) =>
          current.id == route.id ||
          RevvRoute.haversineKm(current.centerPoint, route.centerPoint) <
              dedupeDistanceKm,
    );
    if (!isNearDuplicate) {
      pool.add(route);
    }
  }
  pool.sort((a, b) => recommendationScore(b).compareTo(recommendationScore(a)));
  return pool.take(limit).toList();
}

List<RevvRoute> filterRoutesForStrength(
  Iterable<RevvRoute> routes,
  RouteFilterStrength strength,
) {
  return routes.where((route) {
    return switch (strength) {
      RouteFilterStrength.precise => _passesPreciseFilter(route),
      RouteFilterStrength.balanced => _passesBalancedFilter(route),
      RouteFilterStrength.broad => _passesBroadFilter(route),
    };
  }).toList();
}

bool _passesPreciseFilter(RevvRoute route) {
  if (route.distanceKm < 3.0) return false;
  if (routeRejectReason(route) != null) return false;
  if (recommendationTier(route) != 'keep') return false;
  if (route.isFacilityLike || route.isPrivateLike) return false;
  if (route.isConnectorLike || route.isMajorRoadLike || route.isBridgeLike) {
    return false;
  }
  return true;
}

bool _passesBalancedFilter(RevvRoute route) {
  return route.distanceKm >= 3.0 && route.qualityRejectReason == null;
}

bool _passesBroadFilter(RevvRoute route) {
  if (route.distanceKm < 3.0) return false;
  if (route.isFacilityLike || hasFacilityLikeName(route.name)) return false;
  if (route.isPrivateLike) return false;
  if (route.isConnectorLike || isConnectorLikeRouteName(route.name)) {
    return false;
  }
  if (hasNumericOnlyName(route.name) && route.distanceKm < 8.0) return false;
  if (route.stopSignCount >= 5 && route.distanceKm < 12.0) return false;
  if (route.stopControlDensity >= 0.65 && route.maxContinuousKm < 1.2) {
    return false;
  }
  return true;
}

double routePolylineOverlapRatio(RevvRoute a, RevvRoute b) {
  if (a.nodes.isEmpty || b.nodes.isEmpty) return 0;
  final sampleA = _sampleRouteNodesForOverlap(a.nodes);
  final sampleB = _sampleRouteNodesForOverlap(b.nodes);
  if (sampleA.isEmpty || sampleB.isEmpty) return 0;

  var nearCount = 0;
  for (final point in sampleA) {
    final near = sampleB.any(
      (other) => RevvRoute.haversineKm(point, other) < 0.18,
    );
    if (near) nearCount++;
  }
  return nearCount / sampleA.length;
}

List<LatLng> _sampleRouteNodesForOverlap(List<LatLng> nodes) {
  if (nodes.length <= 24) return nodes;
  final step = nodes.length / 24;
  return List.generate(24, (i) => nodes[(i * step).floor()]);
}

bool areRoutesNearDuplicate(
  RevvRoute a,
  RevvRoute b, {
  double centerDistanceKm = 3.0,
}) {
  if (a.id == b.id) return true;
  final centerDistance = RevvRoute.haversineKm(a.centerPoint, b.centerPoint);
  if (centerDistance < centerDistanceKm) return true;

  final aName = normalizeRouteName(a.name).toLowerCase();
  final bName = normalizeRouteName(b.name).toLowerCase();
  if (aName.isNotEmpty &&
      bName.isNotEmpty &&
      aName == bName &&
      centerDistance < centerDistanceKm * 2.2) {
    return true;
  }

  if (centerDistance < centerDistanceKm * 2.0) {
    final overlap = math.max(
      routePolylineOverlapRatio(a, b),
      routePolylineOverlapRatio(b, a),
    );
    if (overlap >= 0.42) return true;
  }

  return false;
}

List<RevvRoute> diversifyRouteSlots(
  List<RevvRoute> routes, {
  int limit = defaultVisibleRoutes,
}) {
  if (routes.length <= 2) return routes;
  final ranked = List<RevvRoute>.from(routes)
    ..sort((a, b) => recommendationScore(b).compareTo(recommendationScore(a)));
  final selected = <RevvRoute>[];

  bool addCandidate(RevvRoute route, {double centerDistanceKm = 3.0}) {
    if (selected.length >= limit) return false;
    if (route.id.startsWith('combo:') &&
        selected.where((r) => r.id.startsWith('combo:')).length >= 2) {
      return false;
    }
    final duplicate = selected.any(
      (current) => areRoutesNearDuplicate(
        current,
        route,
        centerDistanceKm: centerDistanceKm,
      ),
    );
    if (duplicate) return false;
    selected.add(route);
    return true;
  }

  void addFromSlot(
    bool Function(RevvRoute route) test,
    int count, {
    double centerDistanceKm = 3.0,
  }) {
    var added = 0;
    for (final route in ranked.where(test)) {
      if (added >= count || selected.length >= limit) return;
      if (selected.any((current) => current.id == route.id)) continue;
      if (addCandidate(route, centerDistanceKm: centerDistanceKm)) {
        added++;
      }
    }
  }

  // Keep the single strongest recommendation first, then preserve slot order
  // so nearby/tight/sweeper/flow/long routes stay visibly mixed in the UI.
  addCandidate(ranked.first);

  addFromSlot((route) => route.distanceFromUser <= 18, 2);
  addFromSlot((route) => routeCharacter(route) == 'tight_technical', 2);
  addFromSlot((route) => routeCharacter(route) == 'fast_sweeper', 2);
  addFromSlot((route) => routeCharacter(route) == 'rhythmic_flow', 2);
  addFromSlot((route) => route.distanceKm >= 24, 2);
  addFromSlot((route) => route.isLoop, 2, centerDistanceKm: 2.4);
  addFromSlot((route) => route.elevationDelta >= 45, 2);
  addFromSlot((route) => recommendationTier(route) == 'maybe', 2);

  for (final route in ranked) {
    if (selected.length >= limit) break;
    addCandidate(route, centerDistanceKm: 2.4);
  }

  if (selected.length < math.min(limit, minimumVisibleRoutes)) {
    for (final route in ranked) {
      if (selected.length >= limit) break;
      final duplicate = selected.any(
        (current) =>
            areRoutesNearDuplicate(current, route, centerDistanceKm: 1.2),
      );
      if (!duplicate) {
        selected.add(route);
      }
    }
  }

  return selected.take(limit).toList();
}

bool hasMeaningfulDiversityGain(
  List<RevvRoute> existing,
  List<RevvRoute> enriched,
) {
  if (enriched.isEmpty) return false;
  if (existing.isEmpty) return true;
  final existingIds = existing.map((r) => r.id).toSet();
  final newCount = enriched.where((r) => !existingIds.contains(r.id)).length;
  return newCount > 0;
}

bool shouldUseCachedRoutes({
  required LatLng cacheCenter,
  required LatLng targetCenter,
  required int searchRadiusKm,
}) {
  final distanceKm = RevvRoute.haversineKm(cacheCenter, targetCenter);
  final reuseRadiusKm = (searchRadiusKm * 0.75).clamp(20, 60).toDouble();
  return distanceKm <= reuseRadiusKm;
}

bool isRouteFieldCacheReusable({
  required LatLng cacheCenter,
  required LatLng targetCenter,
  required int cacheRadiusKm,
  required int requiredRadiusKm,
  required DateTime fetchedAt,
  required DateTime now,
  required Duration maxAge,
  required double maxCenterDistanceKm,
  bool ignoreAge = false,
}) {
  if (cacheRadiusKm < requiredRadiusKm) return false;
  if (RevvRoute.haversineKm(cacheCenter, targetCenter) > maxCenterDistanceKm) {
    return false;
  }
  return ignoreAge || now.difference(fetchedAt) <= maxAge;
}

bool looksLikeEmptyOverpassPayload(String body) {
  final compact = body.replaceAll(RegExp(r'\s+'), '');
  return compact.contains('"elements":[]');
}

List<int> buildSearchRadiusPlan(int baseRadiusKm) {
  final start = baseRadiusKm.clamp(20, 220);
  final plan = <int>{
    start,
    (start + 30).clamp(20, 220),
    (start + 70).clamp(20, 220),
    (start + 120).clamp(20, 220),
  }.toList()..sort();
  return plan;
}

RouteFilterThresholds thresholdsForStage(RouteSearchStage stage) {
  switch (stage) {
    case RouteSearchStage.strict:
      return const RouteFilterThresholds(
        minLoopDistanceKm: 8.0,
        minLinearDistanceKm: 5.0,
        signalHardLimit: 3,
        totalCurvatureMin: 75,
        minCurvyDistanceKm: 2.4,
        maxContinuousKmMin: 0.8,
        maxStraightRunKmMax: 1.5,
        maxStraightFractionMax: 0.24,
        maxSignalPerKm: 0.16,
        maxIntersectionPerKm: 2.2,
        curvyFractionMin: 0.25,
        curvatureDensityMin: 7.5,
        spreadRatioMin: 0.25,
        elongatedAspectMin: 0.15,
        elongatedCurvyFractionMin: 0.30,
        dedupDistanceKm: 6.0,
        maxSelectedRoutes: targetVisibleRoutes,
      );
    case RouteSearchStage.balanced:
      return const RouteFilterThresholds(
        minLoopDistanceKm: 7.0,
        minLinearDistanceKm: 4.0,
        signalHardLimit: 4,
        totalCurvatureMin: 55,
        minCurvyDistanceKm: 1.9,
        maxContinuousKmMin: 0.45,
        maxStraightRunKmMax: 1.9,
        maxStraightFractionMax: 0.28,
        maxSignalPerKm: 0.2,
        maxIntersectionPerKm: 2.6,
        curvyFractionMin: 0.19,
        curvatureDensityMin: 5.2,
        spreadRatioMin: 0.18,
        elongatedAspectMin: 0.12,
        elongatedCurvyFractionMin: 0.22,
        dedupDistanceKm: 4.4,
        maxSelectedRoutes: maximumVisibleRoutes,
      );
    case RouteSearchStage.expanded:
      return const RouteFilterThresholds(
        minLoopDistanceKm: 6.0,
        minLinearDistanceKm: 3.5,
        signalHardLimit: 5,
        totalCurvatureMin: 42,
        minCurvyDistanceKm: 1.4,
        maxContinuousKmMin: 0.3,
        maxStraightRunKmMax: 2.1,
        maxStraightFractionMax: 0.32,
        maxSignalPerKm: 0.24,
        maxIntersectionPerKm: 3.0,
        curvyFractionMin: 0.16,
        curvatureDensityMin: 4.0,
        spreadRatioMin: 0.12,
        elongatedAspectMin: 0.1,
        elongatedCurvyFractionMin: 0.18,
        dedupDistanceKm: 3.6,
        maxSelectedRoutes: maximumVisibleRoutes,
      );
  }
}

double straightFraction({
  required double distanceKm,
  required double maxStraightRunKm,
}) {
  if (distanceKm <= 0) return 1.0;
  return maxStraightRunKm / distanceKm;
}

bool isStraightDominantRoute({
  required double distanceKm,
  required double curvyDistanceKm,
  required double maxStraightRunKm,
  required RouteFilterThresholds thresholds,
}) {
  if (curvyDistanceKm < thresholds.minCurvyDistanceKm) {
    return true;
  }
  return straightFraction(
        distanceKm: distanceKm,
        maxStraightRunKm: maxStraightRunKm,
      ) >
      thresholds.maxStraightFractionMax;
}

bool canReuseSearchResponse({
  required RouteSearchStage stage,
  required int cachedRadiusM,
  required int requestedRadiusM,
}) {
  if (stage == RouteSearchStage.strict) return false;
  if (cachedRadiusM <= 0 || requestedRadiusM <= 0) return false;
  return cachedRadiusM <= requestedRadiusM;
}

List<String> deriveRouteReasonTags(RevvRoute route) {
  final reasons = <String>[];
  if (route.windingScore >= 6.0) {
    reasons.add('high_score');
  }
  if (route.windingDensityPct >= 0.34) {
    reasons.add('dense_corners');
  }
  if (route.curveStyle == 'SWITCHBACK' && route.tightCurveKm >= 1.4) {
    reasons.add('switchbacks');
  }
  if (route.curveStyle == 'SWEEPER' && route.mediumCurveKm >= 2.2) {
    reasons.add('sweepers');
  }
  if (route.maxContinuousKm >= 1.25 && route.windingDensityPct >= 0.24) {
    reasons.add('continuous_flow');
  }
  if (route.elevationDelta >= 45 && route.windingDensityPct >= 0.18) {
    reasons.add('elevation');
  }
  if (route.isLoop &&
      route.distanceKm >= 12 &&
      route.windingDensityPct >= 0.24) {
    reasons.add('loop');
  }
  return reasons;
}

double routeFunScore(RevvRoute route) {
  if (route.funScore > 0) return route.funScore;

  double score = route.windingScore;
  if (route.tightCurveKm + route.mediumCurveKm >= 1.5) {
    score *=
        1.0 +
        ((route.tightCurveKm + route.mediumCurveKm) / route.distanceKm).clamp(
          0.0,
          0.45,
        );
  }
  if (route.maxContinuousKm >= 1.2) {
    score *= 1.0 + (route.maxContinuousKm / 12).clamp(0.0, 0.18);
  }
  if (route.elevationDelta >= 40) {
    score *= 1.0 + (route.elevationDelta / 250).clamp(0.0, 0.14);
  }
  if (route.isLoop) {
    score *= 1.05;
  }
  return score;
}

double routeFlowScore(RevvRoute route) {
  if (route.flowScore > 0) return route.flowScore;

  final weightedStops = route.stopSignCount + (route.trafficSignalCount * 1.5);
  final density = route.stopControlDensity > 0
      ? route.stopControlDensity
      : weightedStops / math.max(route.distanceKm, 1.0);
  final continuityBoost = route.maxContinuousKm >= 1.5 ? 0.08 : 0.0;
  final inferred = (1.0 - (density * 0.35) + continuityBoost).clamp(0.15, 1.0);
  return inferred;
}

double routeAccessPenalty(RevvRoute route) {
  if (route.driveabilityPenalty > 0) return route.driveabilityPenalty;

  double penalty = 1.0;
  if (!route.isNamed) penalty *= 0.78;
  if (route.isFacilityLike) penalty *= 0.08;
  if (route.isConnectorLike) penalty *= 0.18;
  if (route.isBridgeLike) penalty *= 0.28;
  if (route.isMajorRoadLike) penalty *= 0.55;
  if (route.isPrivateLike) penalty *= 0.18;
  if (hasNumericOnlyName(route.name)) penalty *= 0.48;
  return penalty.clamp(0.05, 1.0);
}

double routeContextAdjustment(RevvRoute route) {
  double adjustment = 1.0;
  if (route.distanceKm < 4.0) {
    adjustment *= 0.05;
  } else if (route.distanceKm < 8.0) {
    adjustment *= 0.82;
  }

  if (route.distanceFromUser > 15) {
    final distancePenalty = route.distanceFromUser >= 80
        ? 0.45
        : 1.0 - ((route.distanceFromUser - 15) / 65) * 0.55;
    adjustment *= distancePenalty.clamp(0.45, 1.0);
  }

  if (route.stopSignCount >= 5 && route.distanceKm < 12) {
    adjustment *= 0.15;
  }
  if (route.stopControlDensity >= 0.65 && route.maxContinuousKm < 1.2) {
    adjustment *= 0.2;
  }
  return adjustment.clamp(0.05, 1.0);
}

double recommendationScore(RevvRoute route) {
  if (route.routeRankScore > 0) {
    return route.routeRankScore;
  }

  return routeFunScore(route) *
      routeFlowScore(route) *
      routeAccessPenalty(route) *
      routeContextAdjustment(route);
}

bool isHardRejectedRecommendation(RevvRoute route) {
  if (route.isFacilityLike) return true;
  if (route.isConnectorLike) return true;
  if (route.distanceKm < 4.0) return true;
  if (hasNumericOnlyName(route.name) && route.distanceKm < 8.0) return true;
  if (route.stopSignCount >= 5 && route.distanceKm < 12.0) return true;
  if (route.stopControlDensity >= 0.65 && route.maxContinuousKm < 1.2) {
    return true;
  }
  return false;
}

String recommendationTier(RevvRoute route) {
  if (isHardRejectedRecommendation(route)) return 'reject';
  if (route.isBridgeLike || route.isConnectorLike) return 'maybe';
  if (route.isMajorRoadLike) return 'maybe';
  if (routeFlowScore(route) < 0.45) return 'maybe';
  if (recommendationScore(route) >= math.max(route.windingScore * 0.6, 3.0)) {
    return 'keep';
  }
  return 'maybe';
}

String routeQualityLabel(RevvRoute route) {
  if (route.qualityLabel.isNotEmpty) return route.qualityLabel;
  return recommendationTier(route);
}

String? routeRejectReason(RevvRoute route) {
  if (route.qualityRejectReason?.isNotEmpty ?? false) {
    return route.qualityRejectReason;
  }
  if (route.isFacilityLike || hasFacilityLikeName(route.name)) {
    return '시설/트랙 성격이 강해 추천 대상에서 제외';
  }
  if (route.isConnectorLike || isConnectorLikeRouteName(route.name)) {
    return '연결도로 성격이 강해 추천 대상에서 제외';
  }
  if (route.isBridgeLike || isBridgeLikeRouteName(route.name)) {
    return '브리지 중심 구간이라 추천 우선순위에서 제외';
  }
  if (route.distanceKm < 4.0) {
    return '너무 짧은 세그먼트라 추천 대상에서 제외';
  }
  if (hasNumericOnlyName(route.name) && route.distanceKm < 8.0) {
    return '설명력이 낮은 짧은 숫자형 구간이라 제외';
  }
  if (route.stopSignCount >= 5 && route.distanceKm < 12.0) {
    return '짧은 거리 대비 stop sign가 많아 흐름이 끊김';
  }
  if (route.stopControlDensity >= 0.65 && route.maxContinuousKm < 1.2) {
    return '정지 제어 밀도가 높고 연속 흐름이 짧음';
  }
  return null;
}

String routeCharacter(RevvRoute route) {
  if (route.routeCharacter.isNotEmpty) return route.routeCharacter;
  final curvyDistance = route.tightCurveKm + route.mediumCurveKm;
  final tightRatio = curvyDistance > 0
      ? route.tightCurveKm / curvyDistance
      : 0.0;
  final mediumRatio = curvyDistance > 0
      ? route.mediumCurveKm / curvyDistance
      : 0.0;
  final rhythm = route.maxContinuousKm >= 1.35 && routeFlowScore(route) >= 0.8;

  if (route.elevationDelta >= 90 && route.maxContinuousKm >= 1.2) {
    return 'hill_climb';
  }
  if (tightRatio >= 0.62 && route.tightCurveKm >= 1.6) {
    return 'tight_technical';
  }
  if (mediumRatio >= 0.68 &&
      route.mediumCurveKm >= 2.2 &&
      route.maxContinuousKm >= 1.4) {
    return 'fast_sweeper';
  }
  if (rhythm && curvyDistance >= 2.0) {
    return 'rhythmic_flow';
  }
  return 'mixed_touring';
}

int _routeTextVariant(RevvRoute route, String salt, int modulo) {
  if (modulo <= 1) return 0;
  final key = '${route.id}|${route.name}|$salt';
  var hash = 0;
  for (final code in key.codeUnits) {
    hash = (hash * 31 + code) & 0x7fffffff;
  }
  return hash % modulo;
}

String _routeDistanceTone(RevvRoute route) {
  if (route.distanceKm < 9) return '짧게 집중해서 타기 좋은';
  if (route.distanceKm >= 28) return '긴 호흡으로 이어지는';
  return '부담 없이 몰입하기 좋은';
}

String _routeFlowTone(RevvRoute route) {
  final flow = routeFlowScore(route);
  if (flow >= 0.86) return '정지 요소가 적어 흐름이 매끄러운';
  if (flow >= 0.62) return '중간중간 리듬을 다시 잡기 좋은';
  return '교차로와 정지 요소를 의식하며 타야 하는';
}

String _routeCurveTone(RevvRoute route) {
  final curvyKm = route.tightCurveKm + route.mediumCurveKm;
  if (curvyKm <= 0.4) return '완만한 굴곡';
  final tightRatio = route.tightCurveKm / curvyKm;
  if (tightRatio >= 0.58) return '타이트한 코너';
  if (tightRatio <= 0.28) return '넓은 스위퍼';
  return '타이트 코너와 스위퍼';
}

String _pickRouteText(RevvRoute route, String salt, List<String> options) {
  return options[_routeTextVariant(route, salt, options.length)];
}

String? routePrimaryReason(RevvRoute route) {
  final persistedReason = route.primaryReason?.trim();
  if (persistedReason?.isNotEmpty ?? false) {
    return persistedReason;
  }

  final distanceTone = _routeDistanceTone(route);
  final flowTone = _routeFlowTone(route);
  final curveTone = _routeCurveTone(route);
  final curvyKm = route.tightCurveKm + route.mediumCurveKm;
  final curveKmText = curvyKm >= 0.5 ? '${curvyKm.toStringAsFixed(1)}km' : '곳곳';
  final continuousText = route.maxContinuousKm >= 0.8
      ? '${route.maxContinuousKm.toStringAsFixed(1)}km'
      : '짧은 구간';
  final elevationText = '${route.elevationDelta.toStringAsFixed(0)}m';

  switch (routeCharacter(route)) {
    case 'tight_technical':
      return _pickRouteText(route, 'tight_reason', [
        '$distanceTone 코스예요. $curveKmText 정도의 $curveTone가 이어져 조향 리듬을 차분히 잡기 좋아요.',
        '$curveTone 비중이 높은 기술형 루트예요. 급하게 밀기보다 코너마다 진입 라인을 확인하기 좋습니다.',
        '${route.distanceDisplay} 안에 조밀한 코너가 모여 있어 짧고 선명하게 집중하기 좋은 루트예요.',
        '$flowTone 루트라 코너 사이 템포를 의식하면 훨씬 깔끔하게 이어집니다.',
      ]);
    case 'fast_sweeper':
      return _pickRouteText(route, 'sweeper_reason', [
        '$distanceTone 스위퍼 루트예요. $continuousText 정도 흐름이 살아 있어 부드러운 조향 연습에 좋아요.',
        '넓은 코너가 중심이라 차분하게 라인을 이어가기 좋은 코스예요.',
        '$flowTone 구간 위주라 끊기지 않는 리듬을 만들기 좋습니다.',
        '${route.distanceDisplay} 동안 완만한 곡선이 이어져 부담 없이 루트 감각을 익히기 좋아요.',
      ]);
    case 'rhythmic_flow':
      return _pickRouteText(route, 'flow_reason', [
        '$flowTone 코스예요. 코너와 직선의 간격이 자연스러워 페이스를 일정하게 잡기 좋습니다.',
        '$continuousText 이상 이어지는 흐름이 있어 길을 읽는 재미가 살아있는 루트예요.',
        '$distanceTone 루트지만 리듬이 끊기지 않아 편하게 몰입하기 좋습니다.',
        '$curveTone가 과하지 않게 섞여 있어 처음 타도 흐름을 잡기 쉬운 편이에요.',
      ]);
    case 'hill_climb':
      return _pickRouteText(route, 'hill_reason', [
        '고도 변화가 약 $elevationText 살아 있는 루트예요. 오르막과 코너가 섞여 길의 입체감이 좋습니다.',
        '$distanceTone 업다운 코스예요. 시야가 바뀌는 구간이 많아 차분한 진입 판단이 중요합니다.',
        '$curveTone와 고도 변화가 같이 나와 단조롭지 않은 드라이브 흐름을 만듭니다.',
        '업힐/다운힐 전환이 있어 속도보다 노면과 시야를 읽는 재미가 있는 루트예요.',
      ]);
    case 'mixed_touring':
      return primaryRouteReason(route) ??
          _pickRouteText(route, 'mixed_reason', [
            '$distanceTone 투어링 루트예요. $curveTone가 적당히 섞여 편하게 길맛을 보기 좋습니다.',
            '$flowTone 드라이브 코스예요. 크게 부담스럽지 않으면서도 지루하지 않은 구성이에요.',
            '${route.distanceDisplay} 안에서 코너와 완만한 구간이 균형 있게 이어지는 루트예요.',
            '처음 고른 루트로도 무난해요. 흐름을 보면서 마음에 드는 구간을 편집해 쓰기 좋습니다.',
          ]);
  }
  return primaryRouteReason(route);
}

String? routeCautionNote(RevvRoute route) {
  final persistedNote = route.cautionNote?.trim();
  if (persistedNote?.isNotEmpty ?? false) {
    return persistedNote;
  }
  final notes = <String>[];
  if (route.stopSignCount > 0 || route.trafficSignalCount > 0) {
    final parts = <String>[];
    if (route.stopSignCount > 0) {
      parts.add('stop sign ${route.stopSignCount}개');
    }
    if (route.trafficSignalCount > 0) {
      parts.add('signal ${route.trafficSignalCount}개');
    }
    notes.add('중간 ${parts.join(', ')}가 있어 흐름이 약간 끊길 수 있음');
  }
  if (routeFlowScore(route) < 0.55 && route.maxContinuousKm < 1.2) {
    notes.add('연속 흐름이 짧아 구간마다 페이스를 다시 잡는 편이 좋음');
  }
  if (route.distanceKm >= 35) {
    notes.add('거리가 긴 편이라 출발 전 연료와 휴식 포인트를 먼저 확인하세요');
  }
  if (route.tightCurveKm >= 2.0 && route.sharpCurveCount >= 8) {
    notes.add('타이트한 코너가 많아 초행이면 시야 확보를 우선하세요');
  }
  if (route.isMajorRoadLike || isMajorRoadLikeRouteName(route.name)) {
    notes.add('일부 구간은 간선도로 성격이 섞일 수 있음');
  }
  if (route.isBridgeLike || isBridgeLikeRouteName(route.name)) {
    notes.add('브리지 연결 구간이 포함될 수 있음');
  }
  if (route.isPrivateLike) {
    notes.add('접근 제한 가능성이 있어 현장 표지와 통행 가능 여부를 확인하세요');
  }
  if (notes.isEmpty) return null;
  return _pickRouteText(route, 'caution_note', notes);
}

RevvRoute hydrateRouteMetadata(RevvRoute route) {
  final persistedReason = route.primaryReason?.trim();
  final persistedNote = route.cautionNote?.trim();
  return route.copyWith(
    qualityLabel: routeQualityLabel(route),
    qualityRejectReason: routeRejectReason(route),
    routeCharacter: routeCharacter(route),
    primaryReason: (persistedReason?.isNotEmpty ?? false)
        ? persistedReason
        : routePrimaryReason(route),
    cautionNote: (persistedNote?.isNotEmpty ?? false)
        ? persistedNote
        : routeCautionNote(route),
  );
}

bool hasCompellingRouteReason(RevvRoute route) {
  return deriveRouteReasonTags(route).isNotEmpty;
}

String? primaryRouteReason(RevvRoute route) {
  final reasons = deriveRouteReasonTags(route);
  if (reasons.contains('switchbacks')) {
    return _pickRouteText(route, 'tag_switchbacks', [
      '타이트한 스위치백이 연속되는 기술적인 드라이브 루트예요.',
      '짧은 간격의 방향 전환이 이어져 라인 선택이 중요한 루트예요.',
      '스위치백 리듬이 살아 있어 조향 타이밍을 연습하기 좋은 코스예요.',
    ]);
  }
  if (reasons.contains('sweepers')) {
    return _pickRouteText(route, 'tag_sweepers', [
      '장쾌한 스위퍼 코너가 리듬감 있게 이어지는 루트예요.',
      '넓은 곡선이 길게 이어져 부드러운 라인을 만들기 좋은 코스예요.',
      '스위퍼 중심이라 급한 조작보다 일정한 조향이 잘 어울리는 루트예요.',
    ]);
  }
  if (reasons.contains('dense_corners')) {
    return _pickRouteText(route, 'tag_dense', [
      '코너가 쉼 없이 이어지는 밀도 높은 와인딩 코스예요.',
      '짧은 거리 안에 굴곡이 압축돼 있어 집중감이 좋은 루트예요.',
      '코너 밀도가 높아 처음부터 끝까지 길을 읽는 재미가 있습니다.',
    ]);
  }
  if (reasons.contains('continuous_flow')) {
    return _pickRouteText(route, 'tag_flow', [
      '긴 호흡으로 몰입하기 좋은 연속 코너 루트예요.',
      '코너 사이 흐름이 잘 이어져 부드럽게 리듬을 만들기 좋습니다.',
      '정지 없이 이어지는 구간이 있어 차분하게 페이스를 잡기 좋은 루트예요.',
    ]);
  }
  if (reasons.contains('elevation')) {
    return _pickRouteText(route, 'tag_elevation', [
      '오르막내리막이 살아있는 드라이브 코스예요.',
      '고도 변화가 더해져 평면적인 루트보다 시야 변화가 풍부합니다.',
      '업다운과 코너가 함께 나와 노면과 시야를 읽는 재미가 있어요.',
    ]);
  }
  if (reasons.contains('loop')) {
    return _pickRouteText(route, 'tag_loop', [
      '출발지로 자연스럽게 돌아오는 흐름 좋은 루프예요.',
      '왕복 부담 없이 한 바퀴 돌기 좋은 루프형 코스예요.',
      '시작과 끝이 자연스럽게 이어져 가볍게 한 세션 잡기 좋습니다.',
    ]);
  }
  if (reasons.contains('high_score')) {
    return _pickRouteText(route, 'tag_score', [
      '와인딩 점수가 높은 검증된 드라이빙 코스예요.',
      'REVV 기준 와인딩 곡률 점수가 높아 드라이브 재미가 뚜렷한 루트예요.',
      '와인딩 코너 구성과 거리 밸런스가 좋아 추천 우선순위가 높은 코스입니다.',
    ]);
  }
  return null;
}

String normalizeRouteName(String name) {
  return name.trim().replaceAll(RegExp(r'\s+'), ' ');
}

bool hasFacilityLikeName(String name) {
  final normalized = normalizeRouteName(name);
  if (normalized.isEmpty) return false;
  return _facilityNamePattern.hasMatch(normalized);
}

bool hasNumericOnlyName(String name) {
  final normalized = normalizeRouteName(name);
  if (normalized.isEmpty) return true;
  return normalized.length >= 5 &&
      _numericOnlyRouteNamePattern.hasMatch(normalized);
}

/// 사용자 노출용 루트 이름. OSM way id 같은 숫자 이름을 그대로 보여주지 않는다.
/// 폴백 순서: 원래 이름 → (enrich된) 실제 도로명 → 커브 성격 + 거리.
String routeDisplayName(RevvRoute route, {AppLanguage? language}) {
  final raw = route.name.trim();
  if (raw.isNotEmpty && !hasNumericOnlyName(raw)) return raw;

  for (final road in route.roadNames) {
    final name = road.trim();
    if (name.isNotEmpty && !hasNumericOnlyName(name)) return name;
  }

  String pick(String ko, String en, String fr) {
    return switch (language) {
      AppLanguage.english => en,
      AppLanguage.french => fr,
      _ => ko,
    };
  }

  final style = switch (route.curveStyle) {
    'SWITCHBACK' => pick('스위치백 코스', 'Switchback run', 'Parcours en lacets'),
    'SWEEPER' => pick('스위퍼 코스', 'Sweeper run', 'Parcours en courbes'),
    _ => pick('와인딩 코스', 'Winding run', 'Parcours sinueux'),
  };
  return '$style ${route.distanceKm.toStringAsFixed(1)}km';
}

bool isBridgeLikeRouteName(String name) {
  final normalized = normalizeRouteName(name);
  if (normalized.isEmpty) return false;
  return _bridgeNamePattern.hasMatch(normalized);
}

bool isConnectorLikeRouteName(String name) {
  final normalized = normalizeRouteName(name);
  if (normalized.isEmpty) return false;
  return _connectorNamePattern.hasMatch(normalized);
}

bool isMajorRoadLikeRouteName(String name) {
  final normalized = normalizeRouteName(name);
  if (normalized.isEmpty) return false;
  return _majorRoadNamePattern.hasMatch(normalized) ||
      isBridgeLikeRouteName(normalized) ||
      isConnectorLikeRouteName(normalized);
}

double routeFootprintDiagonalKm(RevvRoute route) {
  final nodes = route.nodes;
  if (nodes.length < 2) return 0;
  double minLat = nodes.first.lat;
  double maxLat = nodes.first.lat;
  double minLng = nodes.first.lng;
  double maxLng = nodes.first.lng;
  for (final node in nodes) {
    if (node.lat < minLat) minLat = node.lat;
    if (node.lat > maxLat) maxLat = node.lat;
    if (node.lng < minLng) minLng = node.lng;
    if (node.lng > maxLng) maxLng = node.lng;
  }
  return RevvRoute.haversineKm(LatLng(minLat, minLng), LatLng(maxLat, maxLng));
}

bool isCompactFacilityLikeRoute(RevvRoute route) {
  final diagonalKm = routeFootprintDiagonalKm(route);
  final curvyKm = route.tightCurveKm + route.mediumCurveKm;
  final curvyFraction = route.distanceKm > 0 ? curvyKm / route.distanceKm : 0.0;
  return diagonalKm > 0 &&
      diagonalKm < 1.35 &&
      route.distanceKm < 10.5 &&
      (route.isLoop || curvyFraction > 0.42 || route.sharpCurveCount >= 10);
}

bool isLowConfidenceShortRoute(RevvRoute route) {
  return route.distanceKm < 7.5 &&
      !hasCompellingRouteReason(route) &&
      route.distanceFromUser > 2.0;
}

bool shouldRejectLowQualityRoute(RevvRoute route) {
  if (hasFacilityLikeName(route.name)) return true;
  if (isCompactFacilityLikeRoute(route)) return true;
  if (route.isLoop && route.distanceKm < 7.0) return true;
  if (hasNumericOnlyName(route.name) && route.distanceKm < 9.0) return true;
  if (isLowConfidenceShortRoute(route)) return true;
  return false;
}

bool isSegmentLikeCurvyRoad(RevvRoute route) {
  if (route.distanceKm < 3.5) return true;
  if (route.distanceKm < 5.0 && hasFacilityLikeName(route.name)) return true;
  if (route.distanceKm < 5.0 && hasNumericOnlyName(route.name)) return true;
  return false;
}

List<RevvRoute> filterSupabaseRouteCandidates(
  List<RevvRoute> routes, {
  int minimumCount = minimumVisibleRoutes,
}) {
  final filtered = routes
      .where((route) => !isSegmentLikeCurvyRoad(route))
      .toList();
  if (filtered.isNotEmpty) return filtered;

  final namedFallback = routes
      .where(
        (route) =>
            route.distanceKm >= 2.0 &&
            route.name.trim().isNotEmpty &&
            !hasNumericOnlyName(route.name) &&
            !hasFacilityLikeName(route.name),
      )
      .toList();
  if (namedFallback.length >= minimumCount) {
    return namedFallback;
  }
  if (namedFallback.isNotEmpty) {
    return namedFallback;
  }

  return routes.where((route) => route.distanceKm >= 2.0).toList();
}

double routeDriveabilityMultiplier(RevvRoute route) {
  if (route.driveabilityPenalty > 0) {
    return route.driveabilityPenalty.clamp(0.05, 1.0);
  }
  double multiplier = 1.0;
  if (hasNumericOnlyName(route.name)) {
    multiplier *= 0.68;
  }
  if (route.name.trim().isEmpty) {
    multiplier *= 0.6;
  }
  if (isCompactFacilityLikeRoute(route)) {
    multiplier *= 0.45;
  }
  if (!hasCompellingRouteReason(route)) {
    multiplier *= 0.82;
  }
  if (isMajorRoadLikeRouteName(route.name)) {
    multiplier *= 0.7;
  }
  if (route.distanceKm < 9.0) {
    multiplier *= 0.84;
  }
  return multiplier;
}

List<RevvRoute> applyQualityGuardrails(
  List<RevvRoute> pool, {
  int minimumCount = minimumVisibleRoutes,
}) {
  final cleaned = pool
      .where((route) => !shouldRejectLowQualityRoute(route))
      .where((route) => !isHardRejectedRecommendation(route))
      .toList();
  if (cleaned.isEmpty) return const [];

  final keepRoutes = cleaned
      .where((route) => recommendationTier(route) == 'keep')
      .toList();
  if (keepRoutes.length >= minimumCount) {
    return keepRoutes;
  }

  final compelling = cleaned.where(hasCompellingRouteReason).toList();
  if (compelling.length >= minimumCount) {
    return compelling;
  }

  final preferred = cleaned
      .where(
        (route) =>
            recommendationTier(route) == 'keep' ||
            hasCompellingRouteReason(route) ||
            (recommendationScore(route) >= 3.0 &&
                !hasNumericOnlyName(route.name)),
      )
      .where((route) => !hasNumericOnlyName(route.name))
      .toList();
  final keepOnly = preferred
      .where((route) => recommendationTier(route) == 'keep')
      .where((route) => !route.isMajorRoadLike)
      .toList();
  if (keepOnly.length >= minimumCount) {
    return keepOnly;
  }
  if (preferred.isNotEmpty) {
    return preferred;
  }

  final namedFallback = cleaned
      .where(
        (route) =>
            route.name.trim().isNotEmpty &&
            !hasNumericOnlyName(route.name) &&
            !hasFacilityLikeName(route.name),
      )
      .toList();
  if (namedFallback.isNotEmpty) {
    return namedFallback;
  }

  return cleaned;
}

List<RevvRoute> buildCompositeFallbackRoutes(
  List<RevvRoute> routes, {
  int targetCount = targetVisibleRoutes,
  double maxGapKm = 8.0,
}) {
  if (routes.length >= targetCount) return routes;

  final pool = List<RevvRoute>.from(routes);
  for (final chain in buildChainedRoutes(
    routes,
    budget: DriveBudget.any,
    maxGapKm: maxGapKm,
  )) {
    final duplicate = pool.any(
      (route) =>
          route.id == chain.id ||
          RevvRoute.haversineKm(route.centerPoint, chain.centerPoint) < 2.6,
    );
    if (duplicate) continue;
    pool.add(chain);
    if (pool.length >= targetCount) return pool;
  }

  return pool;
}

List<RevvRoute> buildChainedRoutes(
  List<RevvRoute> routes, {
  required DriveBudget budget,
  double maxGapKm = 8.0,
}) {
  final chains = <RevvRoute>[];
  for (final route in routes) {
    _extendRouteChain(
      routes: routes,
      current: [route],
      chains: chains,
      budget: budget,
      maxGapKm: maxGapKm,
    );
  }
  chains.sort((a, b) {
    final aInBudget = driveBudgetMatches(a, budget);
    final bInBudget = driveBudgetMatches(b, budget);
    if (aInBudget != bInBudget) return aInBudget ? -1 : 1;
    final minutes = estimatedDriveMinutes(
      a,
    ).compareTo(estimatedDriveMinutes(b));
    if (minutes != 0) return minutes;
    return recommendationScore(b).compareTo(recommendationScore(a));
  });
  return chains;
}

List<RevvRoute> routesForDriveBudget(
  List<RevvRoute> routes, {
  required DriveBudget budget,
}) {
  if (budget == DriveBudget.any) return routes;
  final singles = routes
      .where((route) => driveBudgetMatches(route, budget))
      .toList(growable: false);
  final seen = singles.map((route) => route.id).toSet();
  final chains = <RevvRoute>[];
  for (final chain in buildChainedRoutes(routes, budget: budget)) {
    if (seen.add(chain.id)) chains.add(chain);
  }
  return [...singles, ...chains];
}

void _extendRouteChain({
  required List<RevvRoute> routes,
  required List<RevvRoute> current,
  required List<RevvRoute> chains,
  required DriveBudget budget,
  required double maxGapKm,
}) {
  if (current.length >= 3) return;
  for (final candidate in routes) {
    if (current.any((route) => route.id == candidate.id)) continue;
    final next = [...current, candidate];
    final combo = _combineRouteChain(next, maxGapKm: maxGapKm);
    if (combo == null) continue;
    final alreadyAdded = chains.any((route) => route.id == combo.id);
    if (!alreadyAdded && driveBudgetMatches(combo, budget)) {
      chains.add(combo);
    }
    _extendRouteChain(
      routes: routes,
      current: next,
      chains: chains,
      budget: budget,
      maxGapKm: maxGapKm,
    );
  }
}

RevvRoute? _combineRouteChain(
  List<RevvRoute> segments, {
  required double maxGapKm,
}) {
  if (segments.length < 2 || segments.length > 3) return null;
  for (final segment in segments) {
    if (!_passesChainSegmentGate(segment)) return null;
  }
  for (var i = 0; i < segments.length; i++) {
    for (var j = i + 1; j < segments.length; j++) {
      final overlap = math.max(
        routePolylineOverlapRatio(segments[i], segments[j]),
        routePolylineOverlapRatio(segments[j], segments[i]),
      );
      if (overlap >= 0.42) return null;
    }
  }

  ({List<LatLng> nodes, double gapKm})? bestPath;
  for (final firstNodes in [
    segments.first.nodes,
    segments.first.nodes.reversed.toList(),
  ]) {
    var orderedNodes = firstNodes;
    var totalGapKm = 0.0;
    var valid = true;
    for (var index = 1; index < segments.length; index++) {
      final next = segments[index];
      final join = _bestRouteJoin(orderedNodes, next.nodes);
      if (join == null ||
          !_passesChainJoinGate(
            previous: segments[index - 1],
            next: next,
            gapKm: join.gapKm,
            maxGapKm: maxGapKm,
          )) {
        valid = false;
        break;
      }
      totalGapKm += join.gapKm;
      final nextNodes = join.reverseNext
          ? next.nodes.reversed.toList()
          : next.nodes;
      orderedNodes = [
        ...orderedNodes,
        if (join.gapKm > 0.15) orderedNodes.last,
        ...nextNodes,
      ];
    }
    if (!valid) continue;
    if (bestPath == null || totalGapKm < bestPath.gapKm) {
      bestPath = (nodes: orderedNodes, gapKm: totalGapKm);
    }
  }
  if (bestPath == null) return null;

  final combinedDistanceKm =
      segments.fold<double>(0, (sum, route) => sum + route.distanceKm) +
      bestPath.gapKm;
  final combinedCurvyKm = segments.fold<double>(
    0,
    (sum, route) => sum + route.tightCurveKm + route.mediumCurveKm,
  );
  final combinedCurvyFraction = combinedDistanceKm > 0
      ? combinedCurvyKm / combinedDistanceKm
      : 0.0;
  if (combinedCurvyFraction < 0.22) return null;

  final avgScore =
      segments.fold<double>(0, (sum, route) => sum + route.windingScore) /
      segments.length;
  final baseScore = avgScore * (1.08 - (bestPath.gapKm / maxGapKm) * 0.18);
  if (baseScore < 5.0) return null;

  final center = LatLng(
    segments.fold<double>(0, (sum, route) => sum + route.centerPoint.lat) /
        segments.length,
    segments.fold<double>(0, (sum, route) => sum + route.centerPoint.lng) /
        segments.length,
  );
  final combo = RevvRoute(
    id: 'combo:${segments.map((route) => route.id).join(':')}',
    name: segments.map((route) => route.name).join(' + '),
    nodes: bestPath.nodes,
    distanceKm: combinedDistanceKm,
    windingScore: baseScore,
    starRating: RevvRoute.toStarRating(baseScore),
    sharpCurveCount: segments.fold<int>(
      0,
      (sum, route) => sum + route.sharpCurveCount,
    ),
    elevationDelta: segments.fold<double>(
      0,
      (sum, route) => sum + route.elevationDelta,
    ),
    centerPoint: center,
    distanceFromUser: segments
        .map((route) => route.distanceFromUser)
        .reduce(math.min),
    tightCurveKm: segments.fold<double>(
      0,
      (sum, route) => sum + route.tightCurveKm,
    ),
    mediumCurveKm: segments.fold<double>(
      0,
      (sum, route) => sum + route.mediumCurveKm,
    ),
    maxContinuousKm: segments.fold<double>(
      0,
      (sum, route) => sum + route.maxContinuousKm,
    ),
    stopSignCount: segments.fold<int>(
      0,
      (sum, route) => sum + route.stopSignCount,
    ),
    trafficSignalCount: segments.fold<int>(
      0,
      (sum, route) => sum + route.trafficSignalCount,
    ),
    stopControlDensity: combinedDistanceKm <= 0
        ? 0
        : segments.fold<int>(
                0,
                (sum, route) =>
                    sum + route.stopSignCount + route.trafficSignalCount,
              ) /
              combinedDistanceKm,
    routeCharacter: 'chain_${segments.length}',
    isLoop: false,
  );
  if (shouldRejectLowQualityRoute(combo)) return null;
  return combo;
}

bool _passesChainSegmentGate(RevvRoute route) {
  if (route.nodes.length < 2) return false;
  if (shouldRejectLowQualityRoute(route)) return false;
  if (!hasCompellingRouteReason(route)) return false;
  if (route.windingScore < 4.9) return false;
  if (route.windingDensityPct < 0.18) return false;
  return true;
}

bool _passesChainJoinGate({
  required RevvRoute previous,
  required RevvRoute next,
  required double gapKm,
  required double maxGapKm,
}) {
  if (gapKm > maxGapKm) return false;
  return gapKm <= (math.min(previous.distanceKm, next.distanceKm) * 0.45);
}

({double gapKm, bool reverseNext})? _bestRouteJoin(
  List<LatLng> currentNodes,
  List<LatLng> nextNodes,
) {
  if (currentNodes.length < 2 || nextNodes.length < 2) return null;
  final pairings = <({double gapKm, bool reverseNext})>[
    (
      gapKm: RevvRoute.haversineKm(currentNodes.last, nextNodes.first),
      reverseNext: false,
    ),
    (
      gapKm: RevvRoute.haversineKm(currentNodes.last, nextNodes.last),
      reverseNext: true,
    ),
  ]..sort((x, y) => x.gapKm.compareTo(y.gapKm));
  return pairings.first;
}

String routeStageLabel(RouteSearchStage stage) {
  switch (stage) {
    case RouteSearchStage.strict:
      return 'strict';
    case RouteSearchStage.balanced:
      return 'balanced';
    case RouteSearchStage.expanded:
      return 'expanded';
  }
}

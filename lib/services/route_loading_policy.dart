import 'dart:math' as math;

import '../models/revv_route.dart';

const targetVisibleRoutes = 10;
const minimumVisibleRoutes = 8;
const maximumVisibleRoutes = 12;

enum RouteSearchStage { strict, balanced, expanded }

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
    if (includePrimary)
      wayClause('primary'),
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
          RevvRoute.haversineKm(current.centerPoint, route.centerPoint) < dedupeDistanceKm,
    );
    if (!isNearDuplicate) {
      pool.add(route);
    }
  }
  pool.sort((a, b) => b.windingScore.compareTo(a.windingScore));
  return pool.take(limit).toList();
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

bool looksLikeEmptyOverpassPayload(String body) {
  final compact = body.replaceAll(RegExp(r'\s+'), '');
  return compact.contains('"elements":[]');
}

List<int> buildSearchRadiusPlan(int baseRadiusKm) {
  final start = baseRadiusKm.clamp(20, 120);
  return [start, start + 20, start + 50];
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
  if (route.isLoop && route.distanceKm >= 12 && route.windingDensityPct >= 0.24) {
    reasons.add('loop');
  }
  return reasons;
}

bool hasCompellingRouteReason(RevvRoute route) {
  return deriveRouteReasonTags(route).isNotEmpty;
}

String? primaryRouteReason(RevvRoute route) {
  final reasons = deriveRouteReasonTags(route);
  if (reasons.contains('switchbacks')) {
    return '타이트 코너 감각이 분명한 스위치백 성향 루트예요.';
  }
  if (reasons.contains('sweepers')) {
    return '리듬감 있게 이어지는 스위퍼 코너가 좋은 루트예요.';
  }
  if (reasons.contains('dense_corners')) {
    return '코너가 끊기지 않고 이어지는 와인딩 루트예요.';
  }
  if (reasons.contains('continuous_flow')) {
    return '호흡 길게 몰입하기 좋은 연속 코너 구간이 있어요.';
  }
  if (reasons.contains('elevation')) {
    return '고저차가 살아 있어 드라이브 감각이 더 좋은 코스예요.';
  }
  if (reasons.contains('loop')) {
    return '되돌아오기 편하면서도 흐름이 살아 있는 루프예요.';
  }
  if (reasons.contains('high_score')) {
    return '와인딩 밀도가 높은 핵심 드라이브 코스예요.';
  }
  return null;
}

List<RevvRoute> buildCompositeFallbackRoutes(
  List<RevvRoute> routes, {
  int targetCount = targetVisibleRoutes,
  double maxGapKm = 8.0,
}) {
  if (routes.length >= targetCount) return routes;

  final pool = List<RevvRoute>.from(routes);
  final combos = <RevvRoute>[];

  for (int i = 0; i < routes.length; i++) {
    for (int j = i + 1; j < routes.length; j++) {
      final a = routes[i];
      final b = routes[j];
      if (a.nodes.length < 2 || b.nodes.length < 2) continue;

      final pairings = <({double gapKm, bool reverseA, bool reverseB})>[
        (
          gapKm: RevvRoute.haversineKm(a.nodes.last, b.nodes.first),
          reverseA: false,
          reverseB: false,
        ),
        (
          gapKm: RevvRoute.haversineKm(a.nodes.last, b.nodes.last),
          reverseA: false,
          reverseB: true,
        ),
        (
          gapKm: RevvRoute.haversineKm(a.nodes.first, b.nodes.first),
          reverseA: true,
          reverseB: false,
        ),
        (
          gapKm: RevvRoute.haversineKm(a.nodes.first, b.nodes.last),
          reverseA: true,
          reverseB: true,
        ),
      ]..sort((x, y) => x.gapKm.compareTo(y.gapKm));

      final best = pairings.first;
      final gapKm = best.gapKm;
      if (gapKm > maxGapKm) continue;
      if (!hasCompellingRouteReason(a) || !hasCompellingRouteReason(b)) continue;
      if (a.windingScore < 4.9 || b.windingScore < 4.9) continue;
      if (a.windingDensityPct < 0.18 || b.windingDensityPct < 0.18) continue;
      if (gapKm > (math.min(a.distanceKm, b.distanceKm) * 0.45)) continue;

      final aNodes = best.reverseA ? a.nodes.reversed.toList() : a.nodes;
      final bNodes = best.reverseB ? b.nodes.reversed.toList() : b.nodes;
      final combinedDistanceKm = a.distanceKm + b.distanceKm + gapKm;
      final combinedCurvyKm =
          a.tightCurveKm + a.mediumCurveKm + b.tightCurveKm + b.mediumCurveKm;
      final combinedCurvyFraction =
          combinedDistanceKm > 0 ? combinedCurvyKm / combinedDistanceKm : 0.0;
      if (combinedCurvyFraction < 0.22) continue;

      final mergedNodes = <LatLng>[
        ...aNodes,
        if (gapKm > 0.15) aNodes.last,
        ...bNodes,
      ];
      final center = LatLng(
        (a.centerPoint.lat + b.centerPoint.lat) / 2,
        (a.centerPoint.lng + b.centerPoint.lng) / 2,
      );
      final baseScore = ((a.windingScore + b.windingScore) / 2) * (1.08 - (gapKm / maxGapKm) * 0.18);
      if (baseScore < 5.0) continue;
      final combo = RevvRoute(
        id: 'combo:${a.id}:${b.id}',
        name: '${a.name} + ${b.name}',
        nodes: mergedNodes,
        distanceKm: combinedDistanceKm,
        windingScore: baseScore,
        starRating: RevvRoute.toStarRating(baseScore),
        sharpCurveCount: a.sharpCurveCount + b.sharpCurveCount,
        centerPoint: center,
        distanceFromUser: a.distanceFromUser < b.distanceFromUser
            ? a.distanceFromUser
            : b.distanceFromUser,
        tightCurveKm: a.tightCurveKm + b.tightCurveKm,
        mediumCurveKm: a.mediumCurveKm + b.mediumCurveKm,
        maxContinuousKm: a.maxContinuousKm + b.maxContinuousKm,
        isLoop: false,
      );

      final duplicate = pool.any(
        (route) =>
            route.id == combo.id ||
            RevvRoute.haversineKm(route.centerPoint, combo.centerPoint) < 2.6,
      );
      if (!duplicate) {
        combos.add(combo);
        pool.add(combo);
        if (pool.length >= targetCount) {
          return pool;
        }
      }
    }
  }

  return pool;
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

import 'dart:math' as math;

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

String? routePrimaryReason(RevvRoute route) {
  if (route.primaryReason?.isNotEmpty ?? false) {
    return route.primaryReason;
  }

  switch (routeCharacter(route)) {
    case 'tight_technical':
      return '타이트한 코너 비중이 높아 기술적으로 재미있는 루트예요.';
    case 'fast_sweeper':
      return '길게 이어지는 스위퍼 코너가 리듬감 있게 이어지는 루트예요.';
    case 'rhythmic_flow':
      return '중간 정지가 적고 코너 리듬이 잘 이어지는 루트예요.';
    case 'hill_climb':
      return '고도 변화가 살아 있어 업힐 몰입감이 좋은 루트예요.';
    case 'mixed_touring':
      return primaryRouteReason(route) ?? '커브와 흐름의 균형이 괜찮은 투어링 성향 루트예요.';
  }
  return primaryRouteReason(route);
}

String? routeCautionNote(RevvRoute route) {
  if (route.cautionNote?.isNotEmpty ?? false) {
    return route.cautionNote;
  }
  if (route.stopSignCount > 0 || route.trafficSignalCount > 0) {
    final parts = <String>[];
    if (route.stopSignCount > 0) {
      parts.add('stop sign ${route.stopSignCount}개');
    }
    if (route.trafficSignalCount > 0) {
      parts.add('signal ${route.trafficSignalCount}개');
    }
    return '중간 ${parts.join(', ')}가 있어 흐름이 약간 끊길 수 있음';
  }
  if (route.isMajorRoadLike || isMajorRoadLikeRouteName(route.name)) {
    return '일부 구간은 간선도로 성격이 섞일 수 있음';
  }
  if (route.isBridgeLike || isBridgeLikeRouteName(route.name)) {
    return '브리지 연결 구간이 포함될 수 있음';
  }
  return null;
}

RevvRoute hydrateRouteMetadata(RevvRoute route) {
  return route.copyWith(
    qualityLabel: routeQualityLabel(route),
    qualityRejectReason: routeRejectReason(route),
    routeCharacter: routeCharacter(route),
    primaryReason: routePrimaryReason(route),
    cautionNote: routeCautionNote(route),
  );
}

bool hasCompellingRouteReason(RevvRoute route) {
  return deriveRouteReasonTags(route).isNotEmpty;
}

String? primaryRouteReason(RevvRoute route) {
  final reasons = deriveRouteReasonTags(route);
  if (reasons.contains('switchbacks')) {
    return '타이트한 스위치백이 연속되는 기술적인 드라이브 루트예요.';
  }
  if (reasons.contains('sweepers')) {
    return '장쾌한 스위퍼 코너가 리듬감 있게 이어지는 루트예요.';
  }
  if (reasons.contains('dense_corners')) {
    return '코너가 쉼 없이 이어지는 밀도 높은 와인딩 코스예요.';
  }
  if (reasons.contains('continuous_flow')) {
    return '긴 호흡으로 몰입하기 좋은 연속 코너 루트예요.';
  }
  if (reasons.contains('elevation')) {
    return '오르막내리막이 살아있는 드라이브 코스예요.';
  }
  if (reasons.contains('loop')) {
    return '출발지로 자연스럽게 돌아오는 흐름 좋은 루프예요.';
  }
  if (reasons.contains('high_score')) {
    return '와인딩 점수가 높은 검증된 드라이빙 코스예요.';
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
      if (shouldRejectLowQualityRoute(a) || shouldRejectLowQualityRoute(b)) {
        continue;
      }
      if (!hasCompellingRouteReason(a) || !hasCompellingRouteReason(b)) {
        continue;
      }
      if (a.windingScore < 4.9 || b.windingScore < 4.9) continue;
      if (a.windingDensityPct < 0.18 || b.windingDensityPct < 0.18) continue;
      if (gapKm > (math.min(a.distanceKm, b.distanceKm) * 0.45)) continue;

      final aNodes = best.reverseA ? a.nodes.reversed.toList() : a.nodes;
      final bNodes = best.reverseB ? b.nodes.reversed.toList() : b.nodes;
      final combinedDistanceKm = a.distanceKm + b.distanceKm + gapKm;
      final combinedCurvyKm =
          a.tightCurveKm + a.mediumCurveKm + b.tightCurveKm + b.mediumCurveKm;
      final combinedCurvyFraction = combinedDistanceKm > 0
          ? combinedCurvyKm / combinedDistanceKm
          : 0.0;
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
      final baseScore =
          ((a.windingScore + b.windingScore) / 2) *
          (1.08 - (gapKm / maxGapKm) * 0.18);
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
      if (shouldRejectLowQualityRoute(combo)) continue;

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

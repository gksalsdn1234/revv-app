import 'dart:math' as math;

import '../models/chain_candidate.dart';
import '../models/composite_route.dart';
import '../models/revv_route.dart';

List<ChainCandidate> buildChainCandidates({
  required RevvRoute baseRoute,
  required List<RevvRoute> allRoutes,
  int limit = 3,
}) {
  if (baseRoute.nodes.length < 2) return const [];

  final candidates = <ChainCandidate>[];
  for (final route in allRoutes) {
    if (route.id == baseRoute.id || route.nodes.length < 2) continue;
    if (_looksDuplicated(baseRoute, route)) continue;

    final forward = _buildCandidate(
      baseRoute: baseRoute,
      route: route,
      entryMode: ChainEntryMode.forward,
    );
    final reverse = _buildCandidate(
      baseRoute: baseRoute,
      route: route,
      entryMode: ChainEntryMode.reverse,
    );
    final chosen = _pickBetterCandidate(forward, reverse);
    if (chosen != null) candidates.add(chosen);
  }

  candidates.sort((a, b) => b.mergedRankScore.compareTo(a.mergedRankScore));
  return candidates.take(limit).toList();
}

Future<List<RevvRoute>> ensureChainCandidateNodes({
  required RevvRoute baseRoute,
  required List<RevvRoute> allRoutes,
  required Future<List<LatLng>> Function(String routeId) loadNodes,
  int maxHydratedCandidates = 6,
}) async {
  if (baseRoute.nodes.length < 2) return allRoutes;
  final endpoint = baseRoute.nodes.last;
  final nearby = allRoutes
      .where((route) => route.id != baseRoute.id)
      .where((route) => route.nodes.isEmpty)
      .map((route) => (route: route, gapKm: RevvRoute.haversineKm(endpoint, route.centerPoint)))
      .where((item) => item.gapKm <= 12.0)
      .toList()
    ..sort((a, b) => a.gapKm.compareTo(b.gapKm));

  if (nearby.isEmpty) return allRoutes;

  final hydratedById = <String, RevvRoute>{};
  for (final item in nearby.take(maxHydratedCandidates)) {
    final nodes = await loadNodes(item.route.id);
    if (nodes.length < 2) continue;
    hydratedById[item.route.id] = item.route.copyWith(nodes: nodes);
  }

  if (hydratedById.isEmpty) return allRoutes;
  return allRoutes
      .map((route) => hydratedById[route.id] ?? route)
      .toList();
}

ChainCandidate? _pickBetterCandidate(ChainCandidate? a, ChainCandidate? b) {
  if (a == null) return b;
  if (b == null) return a;
  return a.mergedRankScore >= b.mergedRankScore ? a : b;
}

ChainCandidate? _buildCandidate({
  required RevvRoute baseRoute,
  required RevvRoute route,
  required ChainEntryMode entryMode,
}) {
  final baseExit = baseRoute.nodes.last;
  final targetNodes =
      entryMode == ChainEntryMode.forward ? route.nodes : route.nodes.reversed.toList();
  final targetEntry = targetNodes.first;
  final gapKm = RevvRoute.haversineKm(baseExit, targetEntry);
  if (gapKm > 5.0) return null;

  final headingDelta = _headingDelta(
    baseRoute.nodes[baseRoute.nodes.length - 2],
    baseExit,
    targetNodes[0],
    targetNodes[1],
  );
  if (headingDelta > 145) return null;

  if (route.isFacilityLike || route.isBridgeLike) return null;
  if (route.isConnectorLike && route.routeRankScore < 3.5) return null;
  if (route.flowScore > 0 && route.flowScore < 0.45) return null;

  final connectorQualityScore = _connectorQualityScore(
    route: route,
    gapKm: gapKm,
    headingDelta: headingDelta,
  );
  if (connectorQualityScore < 0.35) return null;

  final mergedFunScore = _weightedAverage(
    a: baseRoute.funScore > 0 ? baseRoute.funScore : baseRoute.windingScore,
    aWeight: baseRoute.distanceKm,
    b: route.funScore > 0 ? route.funScore : route.windingScore,
    bWeight: route.distanceKm,
  );
  final mergedFlowScore = _weightedAverage(
    a: _normalizedFlow(baseRoute),
    aWeight: baseRoute.distanceKm,
    b: _normalizedFlow(route),
    bWeight: route.distanceKm,
  );
  if (mergedFlowScore < 0.5) return null;

  final contextAdjustment = _contextAdjustment(
    gapKm: gapKm,
    totalDistanceKm: baseRoute.distanceKm + route.distanceKm,
  );
  final mergedRankScore =
      mergedFunScore * mergedFlowScore * connectorQualityScore * contextAdjustment;

  if (mergedRankScore < 1.8) return null;

  return ChainCandidate(
    route: route,
    entryMode: entryMode,
    gapKm: gapKm,
    headingDelta: headingDelta,
    connectorQualityScore: connectorQualityScore,
    mergedFunScore: mergedFunScore,
    mergedFlowScore: mergedFlowScore,
    mergedRankScore: mergedRankScore,
  );
}

CompositeRoute buildCompositeRoute({
  required RevvRoute baseRoute,
  required ChainCandidate candidate,
  required List<LatLng> connectorPolyline,
}) {
  final connectorDistanceKm = _polylineDistance(connectorPolyline);
  final connectorDurationMinutes = ((connectorDistanceKm / 55.0) * 60).round();
  final targetNodes = candidate.orientedNodes();
  final orientedRoute = candidate.entryMode == ChainEntryMode.forward
      ? candidate.route
      : candidate.route.copyWith(nodes: targetNodes);
  final mergedNodes = <LatLng>[
    ...baseRoute.nodes,
    ..._skipDuplicateConnectorNodes(baseRoute.nodes.last, connectorPolyline),
    ..._skipDuplicateConnectorNodes(
      connectorPolyline.isNotEmpty ? connectorPolyline.last : baseRoute.nodes.last,
      targetNodes,
    ),
  ];

  final totalDistanceKm = baseRoute.distanceKm + candidate.route.distanceKm + connectorDistanceKm;
  final stopSignCount = baseRoute.stopSignCount + candidate.route.stopSignCount;
  final trafficSignalCount =
      baseRoute.trafficSignalCount + candidate.route.trafficSignalCount;
  final stopControlDensity = totalDistanceKm <= 0
      ? 0.0
      : (stopSignCount + trafficSignalCount) / totalDistanceKm;

  return CompositeRoute(
    baseRoute: baseRoute,
    chainedSegments: [orientedRoute],
    connectorLegs: [
      ConnectorLeg(
        polyline: connectorPolyline,
        distanceKm: connectorDistanceKm,
        estimatedDurationMinutes: connectorDurationMinutes,
      ),
    ],
    mergedNodes: mergedNodes,
    totalDistanceKm: totalDistanceKm,
    estimatedDurationMinutes: ((totalDistanceKm / 55.0) * 60).round(),
    funScore: candidate.mergedFunScore,
    flowScore: candidate.mergedFlowScore,
    routeRankScore: candidate.mergedRankScore,
    stopSignCount: stopSignCount,
    trafficSignalCount: trafficSignalCount,
    stopControlDensity: stopControlDensity,
  );
}

double _connectorQualityScore({
  required RevvRoute route,
  required double gapKm,
  required double headingDelta,
}) {
  var score = 1.0;
  score *= gapKm <= 1.0 ? 1.0 : (1.0 - ((gapKm - 1.0) / 4.0) * 0.35).clamp(0.55, 1.0);
  score *= headingDelta <= 30 ? 1.0 : (1.0 - ((headingDelta - 30) / 115.0) * 0.45).clamp(0.5, 1.0);
  if (route.isConnectorLike) score *= 0.55;
  if (route.isBridgeLike) score *= 0.6;
  if (route.isMajorRoadLike) score *= 0.72;
  if (route.isPrivateLike) score *= 0.5;
  return score.clamp(0.0, 1.0);
}

double _contextAdjustment({
  required double gapKm,
  required double totalDistanceKm,
}) {
  var score = 1.0;
  if (totalDistanceKm < 18) score *= 0.88;
  if (totalDistanceKm > 45) score *= 0.92;
  if (gapKm > 3.0) score *= 0.82;
  return score;
}

double _weightedAverage({
  required double a,
  required double aWeight,
  required double b,
  required double bWeight,
}) {
  final total = aWeight + bWeight;
  if (total <= 0) return 0;
  return ((a * aWeight) + (b * bWeight)) / total;
}

double _normalizedFlow(RevvRoute route) {
  if (route.flowScore > 0) return route.flowScore;
  final stopDensity = route.stopControlDensity;
  if (stopDensity > 0) {
    return (1.0 - stopDensity * 0.8).clamp(0.25, 1.0);
  }
  return 0.8;
}

double _headingDelta(LatLng a1, LatLng a2, LatLng b1, LatLng b2) {
  final exitBearing = _bearing(a1, a2);
  final entryBearing = _bearing(b1, b2);
  var delta = (exitBearing - entryBearing).abs() % 360;
  if (delta > 180) delta = 360 - delta;
  return delta;
}

double _bearing(LatLng from, LatLng to) {
  final lat1 = _rad(from.lat);
  final lat2 = _rad(to.lat);
  final dLng = _rad(to.lng - from.lng);
  final y = math.sin(dLng) * math.cos(lat2);
  final x = math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
  return math.atan2(y, x) * 180 / math.pi;
}

double _rad(double deg) => deg * math.pi / 180;

bool _looksDuplicated(RevvRoute a, RevvRoute b) {
  if (a.nodes.isEmpty || b.nodes.isEmpty) return true;
  return RevvRoute.haversineKm(a.centerPoint, b.centerPoint) < 2.5;
}

double _polylineDistance(List<LatLng> nodes) {
  var total = 0.0;
  for (var i = 0; i < nodes.length - 1; i++) {
    total += RevvRoute.haversineKm(nodes[i], nodes[i + 1]);
  }
  return total;
}

List<LatLng> _skipDuplicateConnectorNodes(LatLng anchor, List<LatLng> nodes) {
  if (nodes.isEmpty) return const [];
  if (RevvRoute.haversineKm(anchor, nodes.first) < 0.02) {
    return nodes.skip(1).toList();
  }
  return nodes;
}

import 'revv_route.dart';

class ConnectorLeg {
  final List<LatLng> polyline;
  final double distanceKm;
  final int estimatedDurationMinutes;

  const ConnectorLeg({
    required this.polyline,
    required this.distanceKm,
    required this.estimatedDurationMinutes,
  });
}

class CompositeRoute {
  final RevvRoute baseRoute;
  final List<RevvRoute> chainedSegments;
  final List<ConnectorLeg> connectorLegs;
  final List<LatLng> mergedNodes;
  final double totalDistanceKm;
  final int estimatedDurationMinutes;
  final double funScore;
  final double flowScore;
  final double routeRankScore;
  final int stopSignCount;
  final int trafficSignalCount;
  final double stopControlDensity;

  const CompositeRoute({
    required this.baseRoute,
    required this.chainedSegments,
    required this.connectorLegs,
    required this.mergedNodes,
    required this.totalDistanceKm,
    required this.estimatedDurationMinutes,
    required this.funScore,
    required this.flowScore,
    required this.routeRankScore,
    required this.stopSignCount,
    required this.trafficSignalCount,
    required this.stopControlDensity,
  });

  String get name =>
      [baseRoute.name, ...chainedSegments.map((r) => r.name)].join(' + ');

  RevvRoute toRouteProjection() {
    final center = _centerPoint(mergedNodes);
    final totalTightKm = [
      baseRoute,
      ...chainedSegments,
    ].fold<double>(0, (sum, route) => sum + route.tightCurveKm);
    final totalMediumKm = [
      baseRoute,
      ...chainedSegments,
    ].fold<double>(0, (sum, route) => sum + route.mediumCurveKm);
    final totalContinuousKm = [
      baseRoute,
      ...chainedSegments,
    ].fold<double>(0, (sum, route) => sum + route.maxContinuousKm);
    final projectedWinding = totalDistanceKm <= 0
        ? 0.0
        : (funScore * flowScore).clamp(0.0, 10.0);

    return RevvRoute(
      id: 'composite:${baseRoute.id}:${chainedSegments.map((r) => r.id).join("+")}',
      name: name,
      nodes: mergedNodes,
      distanceKm: totalDistanceKm,
      windingScore: projectedWinding,
      starRating: RevvRoute.toStarRating(projectedWinding),
      sharpCurveCount: [
        baseRoute,
        ...chainedSegments,
      ].fold<int>(0, (sum, route) => sum + route.sharpCurveCount),
      elevationDelta: [
        baseRoute,
        ...chainedSegments,
      ].fold<double>(0, (sum, route) => sum + route.elevationDelta),
      centerPoint: center,
      distanceFromUser: baseRoute.distanceFromUser,
      tightCurveKm: totalTightKm,
      mediumCurveKm: totalMediumKm,
      maxContinuousKm: totalContinuousKm,
      isLoop: false,
      routeRankScore: routeRankScore,
      funScore: funScore,
      flowScore: flowScore,
      driveabilityPenalty: [
        baseRoute,
        ...chainedSegments,
      ].fold<double>(1.0, (score, route) => score * route.driveabilityPenalty),
      stopSignCount: stopSignCount,
      trafficSignalCount: trafficSignalCount,
      stopControlDensity: stopControlDensity,
      roadClassBucket: 'composite',
      isNamed: true,
      isFacilityLike: false,
      isBridgeLike: false,
      isConnectorLike: false,
      isMajorRoadLike: false,
      isPrivateLike: false,
    );
  }

  static LatLng _centerPoint(List<LatLng> nodes) {
    if (nodes.isEmpty) return const LatLng(0, 0);
    final lat = nodes.map((n) => n.lat).reduce((a, b) => a + b) / nodes.length;
    final lng = nodes.map((n) => n.lng).reduce((a, b) => a + b) / nodes.length;
    return LatLng(lat, lng);
  }
}

import 'dart:math' as math;

import '../models/drive_plan.dart';
import '../models/revv_route.dart';

List<List<LatLng>> navigableDrivePlanLegNodes(DrivePlan plan) {
  return [
    for (final leg in plan.legs)
      if (leg.kind != DrivePlanLegKind.rest &&
          leg.nodes.length >= 2 &&
          _hasTravel(leg.nodes))
        List<LatLng>.unmodifiable(leg.nodes),
  ];
}

List<LatLng> navigableDrivePlanNodes(DrivePlan plan) {
  final nodes = <LatLng>[];
  for (final legNodes in navigableDrivePlanLegNodes(plan)) {
    for (final point in legNodes) {
      if (nodes.isEmpty || !_samePoint(nodes.last, point)) nodes.add(point);
    }
  }
  return List<LatLng>.unmodifiable(nodes);
}

RevvRoute buildDrivePlanRoute({
  required DrivePlan plan,
  required List<RevvRoute> windingRoutes,
  required String name,
}) {
  if (windingRoutes.isEmpty) {
    throw ArgumentError.value(
      windingRoutes,
      'windingRoutes',
      'cannot be empty',
    );
  }
  final nodes = navigableDrivePlanNodes(plan);
  if (nodes.length < 2) {
    throw ArgumentError.value(plan, 'plan', 'needs a navigable path');
  }
  final base = windingRoutes.first;
  final distanceKm = plan.legs
      .where((leg) => leg.kind != DrivePlanLegKind.rest)
      .fold<double>(0, (total, leg) => total + leg.distanceKm);
  final windingScore =
      windingRoutes.fold<double>(
        0,
        (total, route) => total + route.windingScore,
      ) /
      windingRoutes.length;
  final roadNames = <String>{
    for (final route in windingRoutes) ...route.roadNames,
  }.toList(growable: false);
  final surfaces = <String>{
    for (final route in windingRoutes)
      if (route.surfaceSummary.trim().isNotEmpty) route.surfaceSummary.trim(),
  }.join(' / ');
  final speedLimits = <String>{
    for (final route in windingRoutes)
      if (route.speedLimitSummary.trim().isNotEmpty)
        route.speedLimitSummary.trim(),
  }.join(' / ');
  final nearbyPois = <String>{
    for (final route in windingRoutes) ...route.nearbyPoiNames,
  }.toList(growable: false);

  return base.copyWith(
    id: '${RevvRoute.chainRouteIdPrefix}${windingRoutes.map((route) => Uri.encodeComponent(route.id)).join('/')}',
    name: name,
    nodes: nodes,
    geometryIsOverview: false,
    geometryParts: const [],
    distanceKm: distanceKm,
    windingScore: windingScore,
    starRating: RevvRoute.toStarRating(windingScore),
    sharpCurveCount: windingRoutes.fold<int>(
      0,
      (total, route) => total + route.sharpCurveCount,
    ),
    elevationDelta: windingRoutes.fold<double>(
      0,
      (total, route) => total + route.elevationDelta,
    ),
    centerPoint: nodes[nodes.length ~/ 2],
    distanceFromUser: 0,
    tightCurveKm: windingRoutes.fold<double>(
      0,
      (total, route) => total + route.tightCurveKm,
    ),
    mediumCurveKm: windingRoutes.fold<double>(
      0,
      (total, route) => total + route.mediumCurveKm,
    ),
    maxContinuousKm: windingRoutes.fold<double>(
      0,
      (longest, route) => math.max(longest, route.maxContinuousKm),
    ),
    isLoop: RevvRoute.haversineKm(nodes.first, nodes.last) <= 3,
    roadNames: roadNames,
    stopSignCount: windingRoutes.fold<int>(
      0,
      (total, route) => total + route.stopSignCount,
    ),
    trafficSignalCount: windingRoutes.fold<int>(
      0,
      (total, route) => total + route.trafficSignalCount,
    ),
    isFacilityLike: windingRoutes.any((route) => route.isFacilityLike),
    isBridgeLike: windingRoutes.any((route) => route.isBridgeLike),
    isConnectorLike: windingRoutes.any((route) => route.isConnectorLike),
    isMajorRoadLike: windingRoutes.any((route) => route.isMajorRoadLike),
    isPrivateLike: windingRoutes.any((route) => route.isPrivateLike),
    surfaceSummary: surfaces,
    speedLimitSummary: speedLimits,
    nearbyPoiNames: nearbyPois,
    // A single leg's profile is not aligned to the composite geometry.
    clearElevationProfile: true,
  );
}

int windingRouteCount(DrivePlan plan) => _windingRouteIds(plan).length;

int activeWindingRouteNumber(DrivePlan plan, double progress) {
  final routeIds = _windingRouteIds(plan);
  final windingCount = routeIds.length;
  if (windingCount == 0) return 0;
  final drivingLegs = plan.legs
      .where((leg) => leg.kind != DrivePlanLegKind.rest)
      .toList(growable: false);
  final distancesKm = [
    for (final leg in drivingLegs) _nodeDistanceKm(leg.nodes),
  ];
  final totalKm = distancesKm.fold<double>(0, (total, km) => total + km);
  if (totalKm <= 0) return 1;

  final targetKm = progress.clamp(0.0, 1.0) * totalKm;
  var distanceKm = 0.0;
  final reachedRouteIds = <String>{};
  for (var index = 0; index < drivingLegs.length; index++) {
    final leg = drivingLegs[index];
    final legEndKm = distanceKm + distancesKm[index];
    if (targetKm <= legEndKm) {
      if (leg.kind == DrivePlanLegKind.winding) {
        final routeId = _windingLegId(leg, index);
        return routeIds.indexOf(routeId) + 1;
      }
      return math.min(reachedRouteIds.length + 1, windingCount);
    }
    if (leg.kind == DrivePlanLegKind.winding) {
      reachedRouteIds.add(_windingLegId(leg, index));
    }
    distanceKm = legEndKm;
  }
  return windingCount;
}

List<String> _windingRouteIds(DrivePlan plan) {
  final ids = <String>[];
  for (var index = 0; index < plan.legs.length; index++) {
    final leg = plan.legs[index];
    if (leg.kind != DrivePlanLegKind.winding) continue;
    final id = _windingLegId(leg, index);
    if (!ids.contains(id)) ids.add(id);
  }
  return ids;
}

String _windingLegId(DrivePlanLeg leg, int index) =>
    leg.route?.id ?? 'winding-leg-$index';

DrivePlanLegKind? activeDrivePlanLegKind(DrivePlan plan, double progress) {
  final drivingLegs = plan.legs
      .where(
        (leg) =>
            leg.kind != DrivePlanLegKind.rest &&
            leg.nodes.length >= 2 &&
            _hasTravel(leg.nodes),
      )
      .toList(growable: false);
  if (drivingLegs.isEmpty) return null;

  final distancesKm = [
    for (final leg in drivingLegs) _nodeDistanceKm(leg.nodes),
  ];
  final totalKm = distancesKm.fold<double>(0, (total, km) => total + km);
  if (totalKm <= 0) return drivingLegs.first.kind;

  final targetKm = progress.clamp(0.0, 1.0) * totalKm;
  var distanceKm = 0.0;
  for (var index = 0; index < drivingLegs.length; index++) {
    distanceKm += distancesKm[index];
    if (targetKm <= distanceKm) return drivingLegs[index].kind;
  }
  return drivingLegs.last.kind;
}

bool _samePoint(LatLng a, LatLng b) {
  return (a.lat - b.lat).abs() <= 0.000001 && (a.lng - b.lng).abs() <= 0.000001;
}

bool _hasTravel(List<LatLng> nodes) {
  for (var index = 1; index < nodes.length; index++) {
    if (!_samePoint(nodes[index - 1], nodes[index])) return true;
  }
  return false;
}

double _nodeDistanceKm(List<LatLng> nodes) {
  var totalKm = 0.0;
  for (var index = 1; index < nodes.length; index++) {
    totalKm += RevvRoute.haversineKm(nodes[index - 1], nodes[index]);
  }
  return totalKm;
}

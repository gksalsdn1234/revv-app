import 'dart:math' as math;

import '../models/drive_plan.dart';
import '../models/revv_route.dart';
import 'route_loading_policy.dart';
import 'route_service.dart';
import 'transit_eta_service.dart';

typedef RouteCandidateLoader =
    Future<List<RevvRoute>> Function(LatLng center, int radiusKm);
typedef TransitLegLoader =
    Future<List<TransitLegEta>> Function(List<LatLng> waypoints);

class DrivePlannerService {
  final RouteCandidateLoader _candidateLoader;
  final TransitLegLoader _transitLegLoader;

  DrivePlannerService({
    RouteCandidateLoader? candidateLoader,
    TransitLegLoader? transitLegLoader,
    RouteService? routeService,
    TransitEtaService? etaService,
  }) : _candidateLoader =
           candidateLoader ??
           _routeServiceLoader(routeService ?? RouteService()),
       _transitLegLoader =
           transitLegLoader ?? (etaService ?? TransitEtaService()).routeLegs;

  Future<DrivePlan?> buildPlan(DrivePlanRequest request) async {
    final candidates = await _corridorCandidates(request);
    final selected = _selectWindingRoutes(candidates, request);
    return _assemblePlan(request, selected);
  }

  static RouteCandidateLoader _routeServiceLoader(RouteService service) {
    return (center, radiusKm) async {
      service.searchRadiusKm = radiusKm;
      await service.fetchRoutes(center.lat, center.lng);
      return service.mapVisualRoutes.isNotEmpty
          ? service.mapVisualRoutes
          : service.routes;
    };
  }

  Future<List<RevvRoute>> _corridorCandidates(DrivePlanRequest request) async {
    final distanceKm = RevvRoute.haversineKm(
      request.origin,
      request.destination,
    );
    final radiusKm = (distanceKm * 0.22).clamp(20.0, 85.0).round();
    final samples = _corridorSamples(request.origin, request.destination);
    final unique = <String, RevvRoute>{};
    for (final sample in samples) {
      try {
        final routes = await _candidateLoader(sample, radiusKm);
        for (final route in routes) {
          unique[route.id] = route;
        }
      } catch (_) {
        continue;
      }
    }

    final quality = unique.values
        .where((route) => route.nodes.length >= 2)
        .where((route) => recommendationTier(route) == 'keep')
        .where((route) => !shouldRejectLowQualityRoute(route))
        .toList();
    return [
      ...quality,
      ...buildChainedRoutes(quality, budget: DriveBudget.any),
    ];
  }

  List<RevvRoute> _selectWindingRoutes(
    List<RevvRoute> routes,
    DrivePlanRequest request,
  ) {
    final budget = request.windingBudgetMinutes;
    if (budget <= 0 || routes.isEmpty) return const [];
    final maxMinutes = math.max(1, (budget * 1.2).floor());
    final ranked = List<RevvRoute>.from(routes)
      ..sort(
        (a, b) => _routeValue(b, request).compareTo(_routeValue(a, request)),
      );

    final selected = <RevvRoute>[];
    var minutes = 0;
    for (final route in ranked) {
      final routeMinutes = estimatedDriveMinutes(route);
      if (minutes + routeMinutes > maxMinutes) continue;
      final overlaps = selected.any((current) {
        return math.max(
              routePolylineOverlapRatio(current, route),
              routePolylineOverlapRatio(route, current),
            ) >=
            0.42;
      });
      if (overlaps) continue;
      selected.add(route);
      minutes += routeMinutes;
    }

    selected.sort(
      (a, b) => _projection(
        a.centerPoint,
        request,
      ).compareTo(_projection(b.centerPoint, request)),
    );
    return selected;
  }

  Future<DrivePlan> _assemblePlan(
    DrivePlanRequest request,
    List<RevvRoute> windingRoutes,
  ) async {
    final oriented = windingRoutes
        .map((route) => _orientedRoute(route, request))
        .toList();
    final transitWaypoints = <LatLng>[request.origin];
    for (final route in oriented) {
      transitWaypoints.add(route.nodes.first);
      transitWaypoints.add(route.nodes.last);
    }
    transitWaypoints.add(request.destination);

    final transitLegs = await _safeTransitLegs(transitWaypoints);
    final legs = <DrivePlanLeg>[];
    var transitIndex = 0;
    for (var i = 0; i < oriented.length; i++) {
      legs.add(_transitPlanLeg(transitLegs[transitIndex]));
      final route = oriented[i];
      legs.add(
        DrivePlanLeg(
          kind: DrivePlanLegKind.winding,
          nodes: route.nodes,
          distanceKm: route.distanceKm,
          estimatedMinutes: estimatedDriveMinutes(route),
          route: route,
        ),
      );
      transitIndex += 2;
    }
    legs.add(_transitPlanLeg(transitLegs[transitIndex]));

    final windingMinutes = legs
        .where((leg) => leg.kind == DrivePlanLegKind.winding)
        .fold<int>(0, (sum, leg) => sum + leg.estimatedMinutes);
    final transitMinutes = legs
        .where((leg) => leg.kind == DrivePlanLegKind.transit)
        .fold<int>(0, (sum, leg) => sum + leg.estimatedMinutes);
    return DrivePlan(
      legs: legs,
      totalMinutes: windingMinutes + transitMinutes,
      windingMinutes: windingMinutes,
      transitMinutes: transitMinutes,
      waypoints: transitWaypoints,
      budgetShortfallMinutes: math.max(
        0,
        request.windingBudgetMinutes - windingMinutes,
      ),
    );
  }

  Future<List<TransitLegEta>> _safeTransitLegs(List<LatLng> waypoints) async {
    try {
      final legs = await _transitLegLoader(waypoints);
      if (legs.length == waypoints.length - 1) return legs;
    } catch (_) {
      return fallbackLegs(waypoints);
    }
    return fallbackLegs(waypoints);
  }

  DrivePlanLeg _transitPlanLeg(TransitLegEta eta) {
    return DrivePlanLeg(
      kind: DrivePlanLegKind.transit,
      nodes: eta.nodes,
      distanceKm: eta.distanceKm,
      estimatedMinutes: eta.estimatedMinutes,
    );
  }

  RevvRoute _orientedRoute(RevvRoute route, DrivePlanRequest request) {
    final first = _projection(route.nodes.first, request);
    final last = _projection(route.nodes.last, request);
    if (first <= last) return route;
    return route.copyWith(nodes: route.nodes.reversed.toList());
  }

  double _routeValue(RevvRoute route, DrivePlanRequest request) {
    final minutes = estimatedDriveMinutes(route);
    final detourCost = 1 + _corridorOffsetKm(route.centerPoint, request);
    return route.windingScore * minutes / detourCost;
  }

  double _corridorOffsetKm(LatLng point, DrivePlanRequest request) {
    final progress = _projection(point, request).clamp(0.0, 1.0);
    final projected = _interpolate(
      request.origin,
      request.destination,
      progress,
    );
    return RevvRoute.haversineKm(point, projected);
  }

  double _projection(LatLng point, DrivePlanRequest request) {
    final dx = request.destination.lng - request.origin.lng;
    final dy = request.destination.lat - request.origin.lat;
    final lengthSquared = dx * dx + dy * dy;
    if (lengthSquared == 0) return 0;
    return ((point.lng - request.origin.lng) * dx +
            (point.lat - request.origin.lat) * dy) /
        lengthSquared;
  }
}

List<LatLng> _corridorSamples(LatLng origin, LatLng destination) {
  final distanceKm = RevvRoute.haversineKm(origin, destination);
  final count = distanceKm < 80
      ? 3
      : distanceKm < 160
      ? 4
      : 5;
  return List.generate(
    count,
    (index) => _interpolate(origin, destination, (index + 1) / (count + 1)),
  );
}

LatLng _interpolate(LatLng origin, LatLng destination, double progress) {
  return LatLng(
    origin.lat + (destination.lat - origin.lat) * progress,
    origin.lng + (destination.lng - origin.lng) * progress,
  );
}

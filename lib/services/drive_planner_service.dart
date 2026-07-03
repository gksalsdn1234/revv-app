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

/// 연속 주행이 이 분을 넘기면 휴식을 삽입한다.
const int restIntervalMinutes = 120;

/// 삽입되는 휴식 1회 길이.
const int restStopMinutes = 15;

/// 같은 목적지에 대한 와인딩 분량 3옵션. 이름은 중립 (강도·스릴 어휘 금지).
enum DrivePlanOptionKind {
  light('light', 0.6),
  standard('standard', 1.0),
  extended('extended', 1.5);

  final String key;
  final double budgetFactor;
  const DrivePlanOptionKind(this.key, this.budgetFactor);
}

class DrivePlanOption {
  final DrivePlanOptionKind kind;
  final int budgetMinutes;
  final DrivePlan plan;

  const DrivePlanOption({
    required this.kind,
    required this.budgetMinutes,
    required this.plan,
  });
}

/// 연속 주행 [restIntervalMinutes]마다 [restStopMinutes] 휴식 leg를 삽입한다.
/// 마지막 leg 뒤(도착 후)에는 삽입하지 않는다. 휴식은 총 소요에 포함된다.
DrivePlan insertRestLegs(DrivePlan plan) {
  if (plan.legs.isEmpty) return plan;

  final legs = <DrivePlanLeg>[];
  var minutesSinceRest = 0;
  var insertedRestMinutes = 0;
  for (var i = 0; i < plan.legs.length; i++) {
    final leg = plan.legs[i];

    if (leg.kind == DrivePlanLegKind.rest) {
      legs.add(leg);
      minutesSinceRest = 0;
      continue;
    }

    if (leg.estimatedMinutes <= 0) {
      legs.add(leg);
      continue;
    }

    var remainingMinutes = leg.estimatedMinutes;
    while (remainingMinutes > 0) {
      final minutesUntilRest = restIntervalMinutes - minutesSinceRest;
      final segmentMinutes = math.min(remainingMinutes, minutesUntilRest);
      legs.add(_legWithEstimatedMinutes(leg, segmentMinutes));
      remainingMinutes -= segmentMinutes;
      minutesSinceRest += segmentMinutes;

      final hasMoreDriving =
          remainingMinutes > 0 || _hasDrivingBeforeNextRest(plan.legs, i);
      if (minutesSinceRest >= restIntervalMinutes && hasMoreDriving) {
        legs.add(
          const DrivePlanLeg(
            kind: DrivePlanLegKind.rest,
            nodes: [],
            distanceKm: 0,
            estimatedMinutes: restStopMinutes,
          ),
        );
        insertedRestMinutes += restStopMinutes;
        minutesSinceRest = 0;
      }
    }
  }
  if (insertedRestMinutes == 0) return plan;

  return DrivePlan(
    legs: legs,
    totalMinutes: plan.totalMinutes + insertedRestMinutes,
    windingMinutes: plan.windingMinutes,
    transitMinutes: plan.transitMinutes,
    restMinutes: plan.restMinutes + insertedRestMinutes,
    waypoints: plan.waypoints,
    budgetShortfallMinutes: plan.budgetShortfallMinutes,
    usesApproximateTransit: plan.usesApproximateTransit,
  );
}

DrivePlanLeg _legWithEstimatedMinutes(DrivePlanLeg leg, int minutes) {
  if (leg.estimatedMinutes == minutes) return leg;
  final distanceRatio = minutes / leg.estimatedMinutes;
  return DrivePlanLeg(
    kind: leg.kind,
    nodes: leg.nodes,
    distanceKm: leg.distanceKm * distanceRatio,
    estimatedMinutes: minutes,
    route: leg.route,
  );
}

bool _hasDrivingBeforeNextRest(List<DrivePlanLeg> legs, int currentIndex) {
  for (var i = currentIndex + 1; i < legs.length; i++) {
    final leg = legs[i];
    if (leg.kind == DrivePlanLegKind.rest) return false;
    if (leg.estimatedMinutes > 0) return true;
  }
  return false;
}

/// 도착 희망 시각까지 완주 가능한 옵션 중 와인딩이 가장 긴 옵션을 추천한다.
/// 아무 옵션도 맞지 않으면 null (UI가 정직하게 안내).
DrivePlanOption? recommendOptionForArrival(
  List<DrivePlanOption> options, {
  required DateTime now,
  required DateTime arriveBy,
}) {
  final availableMinutes = arriveBy.difference(now).inMinutes;
  DrivePlanOption? best;
  for (final option in options) {
    if (option.plan.totalMinutes > availableMinutes) continue;
    if (best == null || option.plan.windingMinutes > best.plan.windingMinutes) {
      best = option;
    }
  }
  return best;
}

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

  /// 같은 목적지의 예산 3옵션(가볍게 ×0.6 / 기본 ×1.0 / 길게 ×1.5)을 만든다.
  /// 후보 수집(회랑 검색)은 1회만 수행해 옵션 간 중복 계산을 없앤다.
  /// 각 옵션에는 휴식 leg가 삽입돼 총 소요에 반영된다.
  Future<List<DrivePlanOption>> buildPlanOptions(
    DrivePlanRequest request,
  ) async {
    final candidates = await _corridorCandidates(request);
    final options = <DrivePlanOption>[];
    for (final kind in DrivePlanOptionKind.values) {
      final budgetMinutes = math.max(
        10,
        (request.windingBudgetMinutes * kind.budgetFactor).round(),
      );
      final scaled = DrivePlanRequest(
        origin: request.origin,
        destination: request.destination,
        windingBudgetMinutes: budgetMinutes,
      );
      final selected = _selectWindingRoutes(candidates, scaled);
      final plan = insertRestLegs(await _assemblePlan(scaled, selected));
      options.add(
        DrivePlanOption(kind: kind, budgetMinutes: budgetMinutes, plan: plan),
      );
    }
    return options;
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
    final oriented =
        windingRoutes.map((route) => _orientedRoute(route, request)).toList()
          ..sort(
            (a, b) => _projection(
              a.nodes.first,
              request,
            ).compareTo(_projection(b.nodes.first, request)),
          );
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
      usesApproximateTransit: transitLegs.any(
        (leg) => leg.usesFallbackGeometry,
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
    final longitudeScale = math.cos(
      ((request.origin.lat + request.destination.lat) / 2) * math.pi / 180,
    );
    final dx = (request.destination.lng - request.origin.lng) * longitudeScale;
    final dy = request.destination.lat - request.origin.lat;
    final lengthSquared = dx * dx + dy * dy;
    if (lengthSquared == 0) return 0;
    return (((point.lng - request.origin.lng) * longitudeScale) * dx +
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

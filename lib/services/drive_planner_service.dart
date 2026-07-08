import 'dart:math' as math;

import '../core/app_language.dart';
import '../models/drive_plan.dart';
import '../models/revv_route.dart';
import 'route_loading_policy.dart';
import 'route_service.dart';
import 'supabase_service.dart';
import 'transit_eta_service.dart';

typedef RouteCandidateLoader =
    Future<List<RevvRoute>> Function(LatLng center, int radiusKm);
typedef TransitLegLoader =
    Future<List<TransitLegEta>> Function(List<LatLng> waypoints);
typedef RouteNodesLoader = Future<List<LatLng>> Function(String routeId);

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

class FreeRoamOption {
  final int headingBucket;
  final RevvRoute leadRoute;
  final int budgetMinutes;
  final DrivePlan plan;

  const FreeRoamOption({
    required this.headingBucket,
    required this.leadRoute,
    required this.budgetMinutes,
    required this.plan,
  });

  String headingLabel(AppLanguage language) {
    return '${_headingLabel(headingBucket, language)} · ${routeDisplayName(leadRoute, language: language)}';
  }
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
    baselineDirectMinutes: plan.baselineDirectMinutes,
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
  final RouteNodesLoader _nodesLoader;

  DrivePlannerService({
    RouteCandidateLoader? candidateLoader,
    TransitLegLoader? transitLegLoader,
    RouteNodesLoader? nodesLoader,
    RouteService? routeService,
    TransitEtaService? etaService,
  }) : _candidateLoader =
           candidateLoader ??
           _routeServiceLoader(routeService ?? RouteService()),
       _transitLegLoader =
           transitLegLoader ?? (etaService ?? TransitEtaService()).routeLegs,
       _nodesLoader =
           nodesLoader ??
           ((routeId) => SupabaseService().fetchRouteNodes(routeId));

  Future<DrivePlan?> buildPlan(DrivePlanRequest request) async {
    final candidates = await _corridorCandidates(request);
    final selected = _selectWindingRoutes(candidates, request);
    return _assemblePlan(request, selected);
  }

  /// 사용자가 고른 루트들을 그대로 이어붙인 플랜 (탐색·랭킹 없음).
  /// 순서는 현위치 기준 최근접 이웃(greedy)으로 정하고 각 루트는 진행 방향으로 orient.
  Future<DrivePlan> buildPlanFromRoutes({
    required LatLng origin,
    required List<RevvRoute> routes,
    LatLng? destination,
  }) async {
    final hydrated = await _hydrateSelectedRoutes(routes);
    final ordered = _greedyOrderedRoutes(origin, hydrated);
    final resolvedDestination =
        destination ?? (ordered.isEmpty ? origin : ordered.last.nodes.last);
    final baselineDirectMinutes = _samePoint(origin, resolvedDestination)
        ? null
        : await _directBaselineMinutes(origin, resolvedDestination);
    if (ordered.isEmpty) {
      final plan = await _assembleOrientedPlan(
        origin: origin,
        destination: resolvedDestination,
        windingRoutes: const [],
        budgetShortfallMinutes: 0,
      );
      return insertRestLegs(
        plan.copyWith(baselineDirectMinutes: baselineDirectMinutes),
      );
    }
    final plan = await _assembleOrientedPlan(
      origin: origin,
      destination: resolvedDestination,
      windingRoutes: ordered,
      budgetShortfallMinutes: 0,
    );
    return insertRestLegs(
      plan.copyWith(baselineDirectMinutes: baselineDirectMinutes),
    );
  }

  /// 목적지 없이 예산(왕복 총 분) 안에서 좋은 방향으로 나갔다 돌아오는 옵션들.
  Future<List<FreeRoamOption>> buildFreeRoamOptions({
    required LatLng origin,
    required int totalBudgetMinutes,
  }) async {
    final radiusKm = ((totalBudgetMinutes / 60) * 45 / 2)
        .clamp(20.0, 85.0)
        .round();
    final candidates = _qualityCandidates(
      await _candidateLoader(origin, radiusKm),
    );
    if (candidates.isEmpty) return const [];

    final buckets = <int, List<RevvRoute>>{};
    for (final route in candidates) {
      buckets
          .putIfAbsent(_headingBucket(origin, route.centerPoint), () => [])
          .add(route);
    }

    double bucketScore(List<RevvRoute> routes) {
      return routes.fold<double>(
        0,
        (sum, route) => sum + recommendationScore(route),
      );
    }

    final rankedBuckets =
        buckets.entries.where((entry) => entry.value.length >= 2).toList()
          ..sort(
            (a, b) => bucketScore(b.value).compareTo(bucketScore(a.value)),
          );

    final routeBudgetMinutes = math.max(1, (totalBudgetMinutes * 0.45).floor());
    final options = <FreeRoamOption>[];
    for (final entry in rankedBuckets.take(3)) {
      final routes = [...entry.value]
        ..sort(
          (a, b) => recommendationScore(b).compareTo(recommendationScore(a)),
        );
      final selected = <RevvRoute>[];
      var selectedMinutes = 0;
      for (final route in routes) {
        if (selected.length >= 3) break;
        final routeMinutes = estimatedDriveMinutes(route);
        if (selectedMinutes + routeMinutes > routeBudgetMinutes) continue;
        selected.add(route);
        selectedMinutes += routeMinutes;
      }
      if (selected.isEmpty) continue;

      final plan = await buildPlanFromRoutes(
        origin: origin,
        routes: selected,
        destination: origin,
      );
      if (plan.totalMinutes > (totalBudgetMinutes * 1.2).ceil()) continue;
      options.add(
        FreeRoamOption(
          headingBucket: entry.key,
          leadRoute: selected.first,
          budgetMinutes: totalBudgetMinutes,
          plan: plan,
        ),
      );
    }
    return options;
  }

  /// 같은 목적지의 예산 3옵션(가볍게 ×0.6 / 기본 ×1.0 / 길게 ×1.5)을 만든다.
  /// 후보 수집(회랑 검색)은 1회만 수행해 옵션 간 중복 계산을 없앤다.
  /// 각 옵션에는 휴식 leg가 삽입돼 총 소요에 반영된다.
  Future<List<DrivePlanOption>> buildPlanOptions(
    DrivePlanRequest request,
  ) async {
    final candidates = await _corridorCandidates(request);
    final baselineDirectMinutes = await _directBaselineMinutes(
      request.origin,
      request.destination,
    );
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
      final plan = insertRestLegs(
        (await _assemblePlan(
          scaled,
          selected,
        )).copyWith(baselineDirectMinutes: baselineDirectMinutes),
      );
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

    // 파인더용 pre-chained combo는 제외한다: combo는 루트 사이 간격(최대
    // 15km)을 노드 직선으로 잇기 때문에 플랜의 와인딩 leg 안에 존재하지 않는
    // 직선이 그려진다. 플래너는 개별 루트를 골라 사이를 실도로 transit으로
    // 조립하는 자체 체인이 있으므로 combo가 필요 없다.
    return _qualityCandidates(unique.values);
  }

  List<RevvRoute> _qualityCandidates(Iterable<RevvRoute> routes) {
    final base = routes
        .where((route) => route.nodes.length >= 2)
        .where((route) => !shouldRejectLowQualityRoute(route))
        .toList();
    final keep = base
        .where((route) => recommendationTier(route) == 'keep')
        .toList();
    return keep.isNotEmpty
        ? keep
        : base.where((route) => recommendationTier(route) != 'reject').toList();
  }

  List<RevvRoute> _selectWindingRoutes(
    List<RevvRoute> routes,
    DrivePlanRequest request,
  ) {
    final budget = request.windingBudgetMinutes;
    if (budget <= 0 || routes.isEmpty) return const [];
    final maxMinutes = math.max(1, (budget * 1.2).floor());
    final corridorKm = RevvRoute.haversineKm(
      request.origin,
      request.destination,
    );
    final maxOffsetKm = math.max(10.0, corridorKm * 0.22);
    final ranked =
        routes
            .where(
              (route) =>
                  _corridorOffsetKm(route.centerPoint, request) <= maxOffsetKm,
            )
            .toList()
          ..sort(
            (a, b) =>
                _routeValue(b, request).compareTo(_routeValue(a, request)),
          );

    final selected = <RevvRoute>[];
    var minutes = 0;
    for (final route in ranked) {
      if (selected.length >= 3) break;
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
      if (_connectorMinutesFromSelected(selected, route, request) >
          routeMinutes) {
        continue;
      }
      selected.add(route);
      minutes += routeMinutes;
    }

    return selected;
  }

  Future<DrivePlan> _assemblePlan(
    DrivePlanRequest request,
    List<RevvRoute> windingRoutes,
  ) async {
    final hydrated = await _hydrateSelectedRoutes(windingRoutes);
    final oriented = _greedyOrderedRoutes(request.origin, hydrated);
    return _assembleOrientedPlan(
      origin: request.origin,
      destination: request.destination,
      windingRoutes: oriented,
      budgetShortfallMinutes: math.max(
        0,
        request.windingBudgetMinutes -
            oriented.fold<int>(
              0,
              (sum, route) => sum + estimatedDriveMinutes(route),
            ),
      ),
    );
  }

  Future<DrivePlan> _assembleOrientedPlan({
    required LatLng origin,
    required LatLng destination,
    required List<RevvRoute> windingRoutes,
    required int budgetShortfallMinutes,
  }) async {
    final transitWaypoints = <LatLng>[origin];
    for (final route in windingRoutes) {
      transitWaypoints.add(route.nodes.first);
      transitWaypoints.add(route.nodes.last);
    }
    transitWaypoints.add(destination);

    final transitLegs = await _safeTransitLegs(transitWaypoints);
    final legs = <DrivePlanLeg>[];
    var transitIndex = 0;
    for (var i = 0; i < windingRoutes.length; i++) {
      legs.add(_transitPlanLeg(transitLegs[transitIndex]));
      final route = windingRoutes[i];
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
      budgetShortfallMinutes: budgetShortfallMinutes,
      usesApproximateTransit: transitLegs.any(
        (leg) => leg.usesFallbackGeometry,
      ),
    );
  }

  Future<List<RevvRoute>> _hydrateSelectedRoutes(List<RevvRoute> routes) async {
    if (routes.isEmpty) return const [];
    return Future.wait(
      routes.map((route) async {
        try {
          final nodes = await _nodesLoader(
            route.id,
          ).timeout(const Duration(seconds: 5));
          if (nodes.length > route.nodes.length) {
            return route.copyWith(nodes: nodes);
          }
        } catch (_) {
          return route;
        }
        return route;
      }),
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

  Future<int?> _directBaselineMinutes(LatLng origin, LatLng destination) async {
    final waypoints = [origin, destination];
    try {
      final legs = await _transitLegLoader(waypoints);
      if (legs.length == waypoints.length - 1) {
        return legs.fold<int>(0, (sum, leg) => sum + leg.estimatedMinutes);
      }
    } catch (_) {
      return null;
    }
    return fallbackLegs(
      waypoints,
    ).fold<int>(0, (sum, leg) => sum + leg.estimatedMinutes);
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

  double _connectorMinutesFromSelected(
    List<RevvRoute> selected,
    RevvRoute candidate,
    DrivePlanRequest request,
  ) {
    if (selected.isEmpty) return 0;
    final entry = _orientedRoute(candidate, request).nodes.first;
    var nearestKm = double.infinity;
    for (final route in selected) {
      nearestKm = math.min(
        nearestKm,
        RevvRoute.haversineKm(route.nodes.first, entry),
      );
      nearestKm = math.min(
        nearestKm,
        RevvRoute.haversineKm(route.nodes.last, entry),
      );
    }
    return nearestKm / 0.75;
  }

  List<RevvRoute> _greedyOrderedRoutes(LatLng origin, List<RevvRoute> routes) {
    final remaining = routes.where((route) => route.nodes.length >= 2).toList();
    final ordered = <RevvRoute>[];
    var current = origin;
    while (remaining.isNotEmpty) {
      remaining.sort((a, b) {
        return _nearestEndpointKm(
          current,
          a,
        ).compareTo(_nearestEndpointKm(current, b));
      });
      final next = _orientedFromPoint(remaining.removeAt(0), current);
      ordered.add(next);
      current = next.nodes.last;
    }
    return ordered;
  }

  RevvRoute _orientedFromPoint(RevvRoute route, LatLng point) {
    final firstKm = RevvRoute.haversineKm(point, route.nodes.first);
    final lastKm = RevvRoute.haversineKm(point, route.nodes.last);
    if (firstKm <= lastKm) return route;
    return route.copyWith(nodes: route.nodes.reversed.toList());
  }

  double _nearestEndpointKm(LatLng point, RevvRoute route) {
    return math.min(
      RevvRoute.haversineKm(point, route.nodes.first),
      RevvRoute.haversineKm(point, route.nodes.last),
    );
  }

  double _routeValue(RevvRoute route, DrivePlanRequest request) {
    final minutes = estimatedDriveMinutes(route);
    final offset = _corridorOffsetKm(route.centerPoint, request);
    final detourCost = 1 + offset + math.pow(offset / 8.0, 2);
    return recommendationScore(route) * math.sqrt(minutes) / detourCost;
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

bool _samePoint(LatLng a, LatLng b) {
  return (a.lat - b.lat).abs() < 0.000001 && (a.lng - b.lng).abs() < 0.000001;
}

int _headingBucket(LatLng origin, LatLng point) {
  final lat1 = origin.lat * math.pi / 180;
  final lat2 = point.lat * math.pi / 180;
  final deltaLng = (point.lng - origin.lng) * math.pi / 180;
  final y = math.sin(deltaLng) * math.cos(lat2);
  final x =
      math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(deltaLng);
  final bearing = (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  return ((bearing + 22.5) % 360 ~/ 45).toInt();
}

String _headingLabel(int bucket, AppLanguage language) {
  const ko = ['북', '북동', '동', '남동', '남', '남서', '서', '북서'];
  const en = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
  const fr = ['N', 'NE', 'E', 'SE', 'S', 'SO', 'O', 'NO'];
  final index = bucket.clamp(0, 7).toInt();
  return switch (language) {
    AppLanguage.korean => ko[index],
    AppLanguage.english => en[index],
    AppLanguage.french => fr[index],
  };
}

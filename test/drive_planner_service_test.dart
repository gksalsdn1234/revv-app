import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/models/drive_plan.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/services/drive_planner_service.dart';
import 'package:revv_app/services/transit_eta_service.dart';

void main() {
  test(
    'greedy planner selects higher winding value within budget band',
    () async {
      final routes = [
        _route(id: 'low', startLng: 0.60, windingScore: 4.5),
        _route(id: 'high', startLng: 0.30, windingScore: 8.0),
      ];
      final service = _service(routes);

      final plan = await service.buildPlan(_request(20));

      final windingIds = _windingIds(plan);
      expect(windingIds, ['high']);
      expect(plan!.windingMinutes, lessThanOrEqualTo(24));
    },
  );

  test(
    'greedy planner excludes overlapping routes and keeps budget tolerance',
    () async {
      final routes = [
        _route(id: 'best', startLng: 0.20, windingScore: 8.0),
        _route(id: 'overlap', startLng: 0.20, windingScore: 7.5),
        _route(id: 'next', startLng: 0.60, windingScore: 7.0),
        _route(
          id: 'too-much',
          startLng: 0.80,
          windingScore: 6.5,
          distanceKm: 40,
        ),
      ];
      final service = _service(routes);

      final plan = await service.buildPlan(_request(40));

      final windingIds = _windingIds(plan);
      expect(windingIds, containsAll(['best', 'next']));
      expect(windingIds, isNot(contains('overlap')));
      expect(plan!.windingMinutes, inInclusiveRange(32, 48));
    },
  );

  test('planner orders winding legs by corridor projection', () async {
    final routes = [
      _route(id: 'late', startLng: 0.70, windingScore: 7.0),
      _route(id: 'early', startLng: 0.25, windingScore: 7.2),
    ];
    final service = _service(routes);

    final plan = await service.buildPlan(_request(45));

    expect(_windingIds(plan), ['early', 'late']);
    final lastTransit = plan!.legs.last;
    expect(lastTransit.kind, DrivePlanLegKind.transit);
    expect(lastTransit.nodes.first.lng, closeTo(0.75, 0.001));
  });

  test(
    'planner uses latitude-scaled projection for diagonal corridors',
    () async {
      final routes = [
        _routeAt(
          id: 'southeast',
          center: const LatLng(43.5, -78.5),
          windingScore: 7.0,
        ),
        _routeAt(
          id: 'northwest',
          center: const LatLng(45.9, -79.5),
          windingScore: 7.0,
        ),
      ];
      final service = _service(routes);

      final plan = await service.buildPlan(
        const DrivePlanRequest(
          origin: LatLng(45.5, -73.6),
          destination: LatLng(44.0, -79.0),
          windingBudgetMinutes: 60,
        ),
      );

      expect(_windingIds(plan), ['northwest', 'southeast']);
    },
  );

  test(
    'planner orders winding visits by entry point instead of center point',
    () async {
      final routes = [
        _routeWithNodes(
          id: 'center-early-entry-late',
          center: const LatLng(0, 3),
          nodes: const [LatLng(0, 6), LatLng(0, 6.2)],
          windingScore: 7.0,
        ),
        _routeWithNodes(
          id: 'center-late-entry-early',
          center: const LatLng(0, 4),
          nodes: const [LatLng(0, 2), LatLng(0, 2.2)],
          windingScore: 7.0,
        ),
      ];
      final service = _service(routes);

      final plan = await service.buildPlan(_request(60));

      expect(_windingIds(plan), [
        'center-late-entry-early',
        'center-early-entry-late',
      ]);
    },
  );

  test('planner does not select a chained route with its segments', () async {
    final routes = [
      _routeWithNodes(
        id: 'segment-a',
        center: const LatLng(0, 0.25),
        nodes: const [LatLng(0, 0.20), LatLng(0, 0.30)],
        windingScore: 7.0,
      ),
      _routeWithNodes(
        id: 'segment-b',
        center: const LatLng(0, 0.34),
        nodes: const [LatLng(0, 0.32), LatLng(0, 0.42)],
        windingScore: 7.0,
      ),
    ];
    final service = _service(routes);

    final plan = await service.buildPlan(_request(80));
    final ids = _windingIds(plan);

    if (ids.any((id) => id.startsWith('combo:'))) {
      expect(ids, isNot(contains('segment-a')));
      expect(ids, isNot(contains('segment-b')));
    }
  });

  test(
    'planner returns direct transit plan when no corridor candidates exist',
    () async {
      final service = _service(const []);

      final plan = await service.buildPlan(_request(30));

      expect(plan, isNotNull);
      expect(plan!.legs, hasLength(1));
      expect(plan.legs.first.kind, DrivePlanLegKind.transit);
      expect(plan.windingMinutes, 0);
      expect(plan.budgetShortfallMinutes, 30);
    },
  );

  test('planner default ETA falls back when Mapbox token is absent', () async {
    final service = DrivePlannerService(
      candidateLoader: (_, _) async => const [],
    );

    final plan = await service.buildPlan(_request(15));

    expect(plan, isNotNull);
    expect(plan!.legs.single.kind, DrivePlanLegKind.transit);
    expect(plan.legs.single.estimatedMinutes, greaterThan(1));
    expect(plan.usesApproximateTransit, isTrue);
  });
}

DrivePlannerService _service(List<RevvRoute> routes) {
  return DrivePlannerService(
    candidateLoader: (_, _) async => routes,
    transitLegLoader: (waypoints) async => fallbackLegs(waypoints),
  );
}

DrivePlanRequest _request(int budget) {
  return DrivePlanRequest(
    origin: const LatLng(0, 0),
    destination: const LatLng(0, 1),
    windingBudgetMinutes: budget,
  );
}

List<String> _windingIds(DrivePlan? plan) {
  return plan!.legs
      .where((leg) => leg.kind == DrivePlanLegKind.winding)
      .map((leg) => leg.route!.id)
      .toList();
}

RevvRoute _route({
  required String id,
  required double startLng,
  required double windingScore,
  double distanceKm = 16,
}) {
  final endLng = startLng + 0.05;
  return RevvRoute(
    id: id,
    name: 'Route $id',
    nodes: [LatLng(0, startLng), LatLng(0, endLng)],
    distanceKm: distanceKm,
    windingScore: windingScore,
    starRating: 4,
    sharpCurveCount: 10,
    centerPoint: LatLng(0, (startLng + endLng) / 2),
    distanceFromUser: 10,
    tightCurveKm: 2.0,
    mediumCurveKm: 2.5,
    maxContinuousKm: 1.5,
    routeRankScore: 10,
    flowScore: 1,
  );
}

RevvRoute _routeAt({
  required String id,
  required LatLng center,
  required double windingScore,
}) {
  return _routeWithNodes(
    id: id,
    center: center,
    nodes: [
      LatLng(center.lat - 0.02, center.lng - 0.02),
      LatLng(center.lat + 0.02, center.lng + 0.02),
    ],
    windingScore: windingScore,
  );
}

RevvRoute _routeWithNodes({
  required String id,
  required LatLng center,
  required List<LatLng> nodes,
  required double windingScore,
}) {
  return RevvRoute(
    id: id,
    name: 'Route $id',
    nodes: nodes,
    distanceKm: 16,
    windingScore: windingScore,
    starRating: 4,
    sharpCurveCount: 10,
    centerPoint: center,
    distanceFromUser: 10,
    tightCurveKm: 2.0,
    mediumCurveKm: 2.5,
    maxContinuousKm: 1.5,
    routeRankScore: 10,
    flowScore: 1,
  );
}

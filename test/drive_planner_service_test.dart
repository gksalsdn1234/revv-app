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
    'planner ranks high recommendation routes over long raw winding routes',
    () async {
      final routes = [
        _route(
          id: 'good-short',
          startLng: 0.20,
          windingScore: 5.0,
          distanceKm: 16,
          routeRankScore: 9.0,
        ),
        _route(
          id: 'raw-long',
          startLng: 0.45,
          windingScore: 10.0,
          distanceKm: 32,
          routeRankScore: 3.0,
        ),
      ];
      final service = _service(routes);

      final plan = await service.buildPlan(_request(40));

      expect(_windingIds(plan), ['good-short']);
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
          center: const LatLng(44.45, -77.38),
          windingScore: 7.0,
        ),
        _routeAt(
          id: 'northwest',
          center: const LatLng(44.98, -75.49),
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
          center: const LatLng(0, 0.30),
          nodes: const [LatLng(0, 0.60), LatLng(0, 0.62)],
          windingScore: 7.0,
        ),
        _routeWithNodes(
          id: 'center-late-entry-early',
          center: const LatLng(0, 0.40),
          nodes: const [LatLng(0, 0.20), LatLng(0, 0.22)],
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

  test('planner hydrates selected winding route nodes', () async {
    final fullNodes = [
      const LatLng(0, 0.20),
      const LatLng(0, 0.23),
      const LatLng(0, 0.25),
    ];
    final service = _service([
      _route(id: 'short', startLng: 0.20, windingScore: 8.0),
    ], nodesLoader: (_) async => fullNodes);

    final plan = await service.buildPlan(_request(20));

    final winding = _windingLegs(plan).single;
    expect(winding.nodes, fullNodes);
    expect(winding.route!.nodes, fullNodes);
  });

  test('planner keeps compact nodes when hydration fails', () async {
    final route = _route(id: 'short', startLng: 0.20, windingScore: 8.0);
    final service = _service([
      route,
    ], nodesLoader: (_) async => throw StateError('offline'));

    final plan = await service.buildPlan(_request(20));

    final winding = _windingLegs(plan).single;
    expect(winding.nodes, route.nodes);
  });

  test('planner orients routes after hydration', () async {
    final service = _service(
      [_route(id: 'reverse', startLng: 0.45, windingScore: 8.0)],
      nodesLoader: (_) async => const [
        LatLng(0, 0.55),
        LatLng(0, 0.50),
        LatLng(0, 0.45),
      ],
    );

    final plan = await service.buildPlan(_request(20));

    final nodes = _windingLegs(plan).single.nodes;
    expect(nodes.first.lng, closeTo(0.45, 0.001));
    expect(nodes.last.lng, closeTo(0.55, 0.001));
  });

  test('planner excludes routes beyond corridor offset cap', () async {
    final service = _service([
      _routeAt(
        id: 'far-high-score',
        center: const LatLng(1.0, 0.50),
        windingScore: 10.0,
      ),
    ]);

    final plan = await service.buildPlan(_request(30));

    expect(_windingIds(plan), isEmpty);
    expect(plan!.windingMinutes, 0);
  });

  test(
    'planner falls back to maybe routes when no keep route exists',
    () async {
      final service = _service([
        _route(
          id: 'maybe-flow',
          startLng: 0.20,
          windingScore: 8.0,
        ).copyWith(routeRankScore: 0, flowScore: 0.4),
      ]);

      final plan = await service.buildPlan(_request(30));

      expect(_windingIds(plan), ['maybe-flow']);
    },
  );

  test('buildPlanFromRoutes orders selected routes by nearest entry', () async {
    final near = _route(id: 'near', startLng: 0.10, windingScore: 2.0);
    final far = _route(id: 'far', startLng: 0.80, windingScore: 9.0);
    final service = _service(const []);

    final plan = await service.buildPlanFromRoutes(
      origin: const LatLng(0, 0),
      routes: [far, near],
    );

    expect(_windingIds(plan), ['near', 'far']);
  });

  test(
    'buildPlanFromRoutes orients each route toward the current point',
    () async {
      final reversed = _routeWithNodes(
        id: 'reversed',
        center: const LatLng(0, 0.15),
        nodes: const [LatLng(0, 0.30), LatLng(0, 0.10)],
        windingScore: 8,
      );
      final service = _service(const []);

      final plan = await service.buildPlanFromRoutes(
        origin: const LatLng(0, 0),
        routes: [reversed],
      );

      final nodes = _windingLegs(plan).single.nodes;
      expect(nodes.first.lng, closeTo(0.10, 0.001));
      expect(nodes.last.lng, closeTo(0.30, 0.001));
    },
  );

  test('buildPlanFromRoutes defaults destination to last route end', () async {
    final service = _service(const []);

    final plan = await service.buildPlanFromRoutes(
      origin: const LatLng(0, 0),
      routes: [
        _route(id: 'a', startLng: 0.10, windingScore: 7),
        _route(id: 'b', startLng: 0.40, windingScore: 7),
      ],
    );

    expect(plan.waypoints.last.lng, closeTo(0.45, 0.001));
    expect(plan.legs.last.nodes.last.lng, closeTo(0.45, 0.001));
  });

  test(
    'buildPlanFromRoutes uses explicit destination for final transit',
    () async {
      const destination = LatLng(0, 0.90);
      final service = _service(const []);

      final plan = await service.buildPlanFromRoutes(
        origin: const LatLng(0, 0),
        routes: [_route(id: 'a', startLng: 0.10, windingScore: 7)],
        destination: destination,
      );

      expect(plan.waypoints.last, destination);
      expect(plan.legs.last.kind, DrivePlanLegKind.transit);
      expect(plan.legs.last.nodes.last.lng, closeTo(0.90, 0.001));
    },
  );

  test('buildPlanFromRoutes keeps selected low quality routes', () async {
    final rejected = _route(
      id: 'rejected',
      startLng: 0.10,
      windingScore: 1,
    ).copyWith(qualityRejectReason: 'facility');
    final service = _service(const []);

    final plan = await service.buildPlanFromRoutes(
      origin: const LatLng(0, 0),
      routes: [rejected],
    );

    expect(_windingIds(plan), ['rejected']);
  });
}

DrivePlannerService _service(
  List<RevvRoute> routes, {
  RouteNodesLoader? nodesLoader,
}) {
  return DrivePlannerService(
    candidateLoader: (_, _) async => routes,
    transitLegLoader: (waypoints) async => fallbackLegs(waypoints),
    nodesLoader: nodesLoader ?? (_) async => const [],
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
  return _windingLegs(plan).map((leg) => leg.route!.id).toList();
}

List<DrivePlanLeg> _windingLegs(DrivePlan? plan) {
  return plan!.legs
      .where((leg) => leg.kind == DrivePlanLegKind.winding)
      .toList();
}

RevvRoute _route({
  required String id,
  required double startLng,
  required double windingScore,
  double distanceKm = 16,
  double? routeRankScore,
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
    routeRankScore: routeRankScore ?? windingScore,
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

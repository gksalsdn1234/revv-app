import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/core/app_language.dart';
import 'package:revv_app/models/drive_plan.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/services/drive_planner_service.dart';
import 'package:revv_app/services/transit_eta_service.dart';

void main() {
  group('insertRestLegs', () {
    DrivePlanLeg transit(int minutes) => DrivePlanLeg(
      kind: DrivePlanLegKind.transit,
      nodes: const [LatLng(45.5, -73.6), LatLng(45.6, -73.7)],
      distanceKm: 10,
      estimatedMinutes: minutes,
    );

    DrivePlan planOf(List<DrivePlanLeg> legs) {
      final total = legs.fold<int>(0, (sum, leg) => sum + leg.estimatedMinutes);
      return DrivePlan(
        legs: legs,
        totalMinutes: total,
        windingMinutes: 0,
        transitMinutes: total,
        waypoints: const [LatLng(45.5, -73.6), LatLng(45.6, -73.7)],
      );
    }

    test('no rest below the interval', () {
      final plan = insertRestLegs(planOf([transit(60), transit(59)]));
      expect(
        plan.legs.where((leg) => leg.kind == DrivePlanLegKind.rest),
        isEmpty,
      );
      expect(plan.restMinutes, 0);
    });

    test('rest inserted exactly at the interval boundary', () {
      final plan = insertRestLegs(
        planOf([transit(60), transit(60), transit(30)]),
      );
      final restLegs = plan.legs
          .where((leg) => leg.kind == DrivePlanLegKind.rest)
          .toList();
      expect(restLegs, hasLength(1));
      expect(restLegs.first.estimatedMinutes, restStopMinutes);
      // 휴식은 120분 누적 직후(두 번째 leg 뒤)에 삽입된다
      expect(plan.legs[2].kind, DrivePlanLegKind.rest);
      expect(plan.restMinutes, restStopMinutes);
      expect(plan.totalMinutes, 150 + restStopMinutes);
    });

    test('rest is inserted inside a long final leg before arrival', () {
      final plan = insertRestLegs(planOf([transit(121)]));
      final restLegs = plan.legs
          .where((leg) => leg.kind == DrivePlanLegKind.rest)
          .toList();
      expect(restLegs, hasLength(1));
      expect(plan.legs.map((leg) => leg.estimatedMinutes), [120, 15, 1]);
      expect(plan.legs.last.kind, isNot(DrivePlanLegKind.rest));
      expect(plan.restMinutes, restStopMinutes);
      expect(plan.totalMinutes, 121 + restStopMinutes);
    });

    test(
      'long uninterrupted legs get repeated rests before the final segment',
      () {
        final plan = insertRestLegs(planOf([transit(241)]));
        final restLegs = plan.legs
            .where((leg) => leg.kind == DrivePlanLegKind.rest)
            .toList();
        expect(restLegs, hasLength(2));
        expect(plan.legs.map((leg) => leg.estimatedMinutes), [
          120,
          15,
          120,
          15,
          1,
        ]);
        expect(plan.legs.last.kind, isNot(DrivePlanLegKind.rest));
        expect(plan.restMinutes, restStopMinutes * 2);
        expect(plan.totalMinutes, 241 + restStopMinutes * 2);
      },
    );

    test('multiple rests for long drives, none after arrival', () {
      final plan = insertRestLegs(
        planOf([transit(120), transit(120), transit(120)]),
      );
      final restLegs = plan.legs
          .where((leg) => leg.kind == DrivePlanLegKind.rest)
          .toList();
      expect(restLegs, hasLength(2));
      expect(plan.legs.last.kind, isNot(DrivePlanLegKind.rest));
      expect(plan.restMinutes, restStopMinutes * 2);
    });

    test('rest leg survives serialization roundtrip', () {
      final plan = insertRestLegs(planOf([transit(120), transit(20)]));
      final restored = DrivePlan.fromJson(plan.toJson());
      expect(
        restored.legs.map((leg) => leg.kind.value),
        plan.legs.map((leg) => leg.kind.value),
      );
      expect(restored.restMinutes, plan.restMinutes);
      expect(restored.totalMinutes, plan.totalMinutes);
    });
  });

  group('recommendOptionForArrival', () {
    DrivePlanOption option(DrivePlanOptionKind kind, int total, int winding) {
      return DrivePlanOption(
        kind: kind,
        budgetMinutes: winding,
        plan: DrivePlan(
          legs: const [],
          totalMinutes: total,
          windingMinutes: winding,
          transitMinutes: total - winding,
          waypoints: const [],
        ),
      );
    }

    final now = DateTime(2026, 7, 3, 9, 0);
    final options = [
      option(DrivePlanOptionKind.light, 90, 20),
      option(DrivePlanOptionKind.standard, 120, 45),
      option(DrivePlanOptionKind.extended, 180, 90),
    ];

    test('roomy deadline picks the longest winding option', () {
      final picked = recommendOptionForArrival(
        options,
        now: now,
        arriveBy: now.add(const Duration(hours: 4)),
      );
      expect(picked?.kind, DrivePlanOptionKind.extended);
    });

    test('tight deadline drops to the lightest fitting option', () {
      final picked = recommendOptionForArrival(
        options,
        now: now,
        arriveBy: now.add(const Duration(minutes: 100)),
      );
      expect(picked?.kind, DrivePlanOptionKind.light);
    });

    test('impossible deadline returns null', () {
      final picked = recommendOptionForArrival(
        options,
        now: now,
        arriveBy: now.add(const Duration(minutes: 45)),
      );
      expect(picked, isNull);
    });
  });

  group('buildPlanOptions', () {
    RevvRoute route(String id, double lat) => RevvRoute(
      id: id,
      name: 'Route $id',
      nodes: [LatLng(lat, -73.6), LatLng(lat + 0.05, -73.65)],
      distanceKm: 14,
      windingScore: 6.2,
      starRating: 4,
      sharpCurveCount: 9,
      centerPoint: LatLng(lat + 0.02, -73.62),
      distanceFromUser: 5,
      tightCurveKm: 3,
      mediumCurveKm: 4,
      maxContinuousKm: 4,
    );

    test('collects corridor candidates once and scales budgets', () async {
      var loaderCalls = 0;
      final planner = DrivePlannerService(
        candidateLoader: (center, radius) async {
          loaderCalls += 1;
          return [route('a', 45.55), route('b', 45.75), route('c', 45.95)];
        },
        transitLegLoader: (waypoints) async => fallbackLegs(waypoints),
      );

      final options = await planner.buildPlanOptions(
        const DrivePlanRequest(
          origin: LatLng(45.5, -73.6),
          destination: LatLng(46.1, -73.9),
          windingBudgetMinutes: 60,
        ),
      );

      expect(options, hasLength(3));
      expect(options.map((option) => option.kind), DrivePlanOptionKind.values);
      expect(options[0].budgetMinutes, 36);
      expect(options[1].budgetMinutes, 60);
      expect(options[2].budgetMinutes, 90);
      // 회랑 샘플 수(3~5)만큼만 — 옵션마다 재수집하지 않는다
      expect(loaderCalls, lessThanOrEqualTo(5));
    });

    test('adds one direct baseline to every option', () async {
      var directCalls = 0;
      final planner = DrivePlannerService(
        candidateLoader: (center, radius) async {
          return [route('a', 45.55)];
        },
        transitLegLoader: (waypoints) async {
          if (_isDirectBaseline(waypoints)) {
            directCalls += 1;
            return [
              TransitLegEta(
                nodes: waypoints,
                distanceKm: 30,
                estimatedMinutes: 30,
              ),
            ];
          }
          return fallbackLegs(waypoints);
        },
      );

      final options = await planner.buildPlanOptions(
        const DrivePlanRequest(
          origin: LatLng(45.5, -73.6),
          destination: LatLng(46.1, -73.9),
          windingBudgetMinutes: 60,
        ),
      );

      expect(directCalls, 1);
      expect(
        options.map((option) => option.plan.baselineDirectMinutes),
        everyElement(30),
      );
    });

    test('keeps plans without a baseline when direct loader throws', () async {
      final planner = DrivePlannerService(
        candidateLoader: (center, radius) async => const [],
        transitLegLoader: (_) async => throw StateError('offline'),
      );

      final options = await planner.buildPlanOptions(
        const DrivePlanRequest(
          origin: LatLng(45.5, -73.6),
          destination: LatLng(46.1, -73.9),
          windingBudgetMinutes: 60,
        ),
      );

      expect(options, hasLength(3));
      expect(
        options.map((option) => option.plan.baselineDirectMinutes),
        everyElement(isNull),
      );
      expect(
        options.map((option) => option.plan.totalMinutes),
        everyElement(greaterThan(0)),
      );
    });
  });

  group('buildFreeRoamOptions', () {
    test('selects the dense high-score heading bucket first', () async {
      final planner = DrivePlannerService(
        candidateLoader: (_, _) async => [
          _freeRoute('ne-a', 'Chemin Kilkenny', 0.10, 0.10, score: 9),
          _freeRoute('ne-b', 'Route NE', 0.12, 0.11, score: 8),
          _freeRoute('east-a', 'Route E', 0.00, 0.20, score: 5),
          _freeRoute('east-b', 'Route E2', 0.01, 0.22, score: 5),
        ],
        transitLegLoader: _fixedLegs,
      );

      final options = await planner.buildFreeRoamOptions(
        origin: const LatLng(45.5, -73.6),
        totalBudgetMinutes: 60,
      );

      expect(options, isNotEmpty);
      expect(options.first.headingLabel(AppLanguage.korean), contains('북동'));
      expect(
        _freeWindingIds(options.first.plan),
        containsAll(['ne-a', 'ne-b']),
      );
    });

    test(
      'uses half-trip radius and limits selected route minutes to 45 percent',
      () async {
        var requestedRadius = 0;
        final planner = DrivePlannerService(
          candidateLoader: (_, radius) async {
            requestedRadius = radius;
            return [
              _freeRoute('a', 'Route A', 0.10, 0.10, score: 9),
              _freeRoute('b', 'Route B', 0.12, 0.12, score: 8),
              _freeRoute('c', 'Route C', 0.14, 0.14, score: 7),
            ];
          },
          transitLegLoader: _fixedLegs,
        );

        final options = await planner.buildFreeRoamOptions(
          origin: const LatLng(45.5, -73.6),
          totalBudgetMinutes: 60,
        );

        expect(requestedRadius, 23);
        expect(options, hasLength(1));
        expect(options.single.plan.windingMinutes, lessThanOrEqualTo(27));
        expect(_freeWindingIds(options.single.plan), isNot(contains('c')));
      },
    );

    test('builds a loop from origin back to origin', () async {
      const origin = LatLng(45.5, -73.6);
      final planner = DrivePlannerService(
        candidateLoader: (_, _) async => [
          _freeRoute('a', 'Route A', 0.10, 0.10, score: 9),
          _freeRoute('b', 'Route B', 0.12, 0.12, score: 8),
        ],
        transitLegLoader: _fixedLegs,
      );

      final options = await planner.buildFreeRoamOptions(
        origin: origin,
        totalBudgetMinutes: 60,
      );

      final plan = options.single.plan;
      expect(plan.legs.first.nodes.first, origin);
      expect(plan.legs.last.nodes.last, origin);
      expect(plan.waypoints.first, origin);
      expect(plan.waypoints.last, origin);
      expect(plan.baselineDirectMinutes, isNull);
    });

    test('returns empty options when no candidates exist', () async {
      final planner = DrivePlannerService(
        candidateLoader: (_, _) async => const [],
        transitLegLoader: _fixedLegs,
      );

      final options = await planner.buildFreeRoamOptions(
        origin: const LatLng(45.5, -73.6),
        totalBudgetMinutes: 60,
      );

      expect(options, isEmpty);
    });
  });
}

bool _isDirectBaseline(List<LatLng> waypoints) {
  return waypoints.length == 2 &&
      waypoints.first.lat == 45.5 &&
      waypoints.first.lng == -73.6 &&
      waypoints.last.lat == 46.1 &&
      waypoints.last.lng == -73.9;
}

RevvRoute _freeRoute(
  String id,
  String name,
  double latOffset,
  double lngOffset, {
  required double score,
}) {
  final start = LatLng(45.5 + latOffset, -73.6 + lngOffset);
  final end = LatLng(45.5 + latOffset + 0.02, -73.6 + lngOffset + 0.01);
  return RevvRoute(
    id: id,
    name: name,
    nodes: [start, end],
    distanceKm: 8,
    windingScore: 6,
    starRating: 4,
    sharpCurveCount: 6,
    centerPoint: LatLng((start.lat + end.lat) / 2, (start.lng + end.lng) / 2),
    distanceFromUser: 4,
    tightCurveKm: 1.2,
    mediumCurveKm: 1.4,
    maxContinuousKm: 2,
    routeRankScore: score,
    flowScore: 1,
  );
}

Future<List<TransitLegEta>> _fixedLegs(List<LatLng> waypoints) async {
  return [
    for (var i = 0; i < waypoints.length - 1; i++)
      TransitLegEta(
        nodes: [waypoints[i], waypoints[i + 1]],
        distanceKm: 4,
        estimatedMinutes: 5,
      ),
  ];
}

List<String> _freeWindingIds(DrivePlan plan) {
  return [
    for (final leg in plan.legs)
      if (leg.kind == DrivePlanLegKind.winding && leg.route != null)
        leg.route!.id,
  ];
}

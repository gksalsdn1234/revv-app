import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/models/drive_plan.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/services/drive_plan_navigation.dart';

void main() {
  const first = RevvRoute(
    id: 'first',
    name: 'First',
    nodes: [LatLng(0, 1), LatLng(0, 2)],
    distanceKm: 4,
    windingScore: 6,
    starRating: 4,
    sharpCurveCount: 3,
    elevationDelta: 40,
    stopSignCount: 2,
    surfaceSummary: 'asphalt',
    elevationProfile: [100, 150],
    centerPoint: LatLng(0, 1.5),
    distanceFromUser: 0,
  );
  const second = RevvRoute(
    id: 'second',
    name: 'Second',
    nodes: [LatLng(0, 3), LatLng(0, 4)],
    distanceKm: 4,
    windingScore: 8,
    starRating: 5,
    sharpCurveCount: 5,
    elevationDelta: 60,
    trafficSignalCount: 1,
    isBridgeLike: true,
    surfaceSummary: 'gravel',
    elevationProfile: [250, 180],
    centerPoint: LatLng(0, 3.5),
    distanceFromUser: 0,
  );
  const plan = DrivePlan(
    legs: [
      DrivePlanLeg(
        kind: DrivePlanLegKind.transit,
        nodes: [LatLng(0, 0), LatLng(0, 1)],
        distanceKm: 1,
        estimatedMinutes: 2,
      ),
      DrivePlanLeg(
        kind: DrivePlanLegKind.winding,
        nodes: [LatLng(0, 1), LatLng(0, 2)],
        distanceKm: 4,
        estimatedMinutes: 5,
        route: first,
      ),
      DrivePlanLeg(
        kind: DrivePlanLegKind.rest,
        nodes: [],
        distanceKm: 0,
        estimatedMinutes: 10,
      ),
      DrivePlanLeg(
        kind: DrivePlanLegKind.transit,
        nodes: [LatLng(0, 2), LatLng(0, 3)],
        distanceKm: 1,
        estimatedMinutes: 2,
      ),
      DrivePlanLeg(
        kind: DrivePlanLegKind.winding,
        nodes: [LatLng(0, 3), LatLng(0, 4)],
        distanceKm: 4,
        estimatedMinutes: 5,
        route: second,
      ),
      DrivePlanLeg(
        kind: DrivePlanLegKind.transit,
        nodes: [LatLng(0, 4), LatLng(0, 4)],
        distanceKm: 0,
        estimatedMinutes: 0,
      ),
    ],
    totalMinutes: 24,
    windingMinutes: 10,
    transitMinutes: 4,
    restMinutes: 10,
    waypoints: [
      LatLng(0, 0),
      LatLng(0, 1),
      LatLng(0, 2),
      LatLng(0, 3),
      LatLng(0, 4),
    ],
  );

  test('navigableDrivePlanNodes joins every driving leg without seams', () {
    final nodes = navigableDrivePlanNodes(plan);

    expect(nodes, hasLength(5));
    expect(nodes.first, samePoint(const LatLng(0, 0)));
    expect(nodes.last, samePoint(const LatLng(0, 4)));
    expect(navigableDrivePlanLegNodes(plan), hasLength(4));
  });

  test('buildDrivePlanRoute represents the full chain with a composite id', () {
    final route = buildDrivePlanRoute(
      plan: plan,
      windingRoutes: const [first, second],
      name: '루트 체인 · 2개',
    );

    expect(route.id, 'chain:first/second');
    expect(route.isChainRoute, isTrue);
    expect(route.name, '루트 체인 · 2개');
    expect(route.distanceKm, 10);
    expect(route.nodes, hasLength(5));
    expect(route.sharpCurveCount, 8);
    expect(route.stopSignCount, 2);
    expect(route.trafficSignalCount, 1);
    expect(route.isBridgeLike, isTrue);
    expect(route.surfaceSummary, 'asphalt / gravel');
    expect(route.elevationDelta, 100);
    expect(route.elevationProfile, isNull);
  });

  test('activeWindingRouteNumber advances during the connector leg', () {
    expect(activeWindingRouteNumber(plan, 0), 1);
    expect(activeWindingRouteNumber(plan, 0.45), 1);
    expect(activeWindingRouteNumber(plan, 0.55), 2);
    expect(activeWindingRouteNumber(plan, 1), 2);
  });

  test('activeDrivePlanLegKind distinguishes transit from winding', () {
    expect(activeDrivePlanLegKind(plan, 0), DrivePlanLegKind.transit);
    expect(activeDrivePlanLegKind(plan, 0.3), DrivePlanLegKind.winding);
    expect(activeDrivePlanLegKind(plan, 0.55), DrivePlanLegKind.transit);
    expect(activeDrivePlanLegKind(plan, 0.8), DrivePlanLegKind.winding);
    expect(activeDrivePlanLegKind(plan, 1), DrivePlanLegKind.winding);
  });

  test('rest-split legs count one selected winding route', () {
    const splitPlan = DrivePlan(
      legs: [
        DrivePlanLeg(
          kind: DrivePlanLegKind.winding,
          nodes: [LatLng(0, 1), LatLng(0, 1.5)],
          distanceKm: 2,
          estimatedMinutes: 60,
          route: first,
        ),
        DrivePlanLeg(
          kind: DrivePlanLegKind.rest,
          nodes: [],
          distanceKm: 0,
          estimatedMinutes: 10,
        ),
        DrivePlanLeg(
          kind: DrivePlanLegKind.winding,
          nodes: [LatLng(0, 1.5), LatLng(0, 2)],
          distanceKm: 2,
          estimatedMinutes: 60,
          route: first,
        ),
        DrivePlanLeg(
          kind: DrivePlanLegKind.transit,
          nodes: [LatLng(0, 2), LatLng(0, 3)],
          distanceKm: 1,
          estimatedMinutes: 2,
        ),
        DrivePlanLeg(
          kind: DrivePlanLegKind.winding,
          nodes: [LatLng(0, 3), LatLng(0, 4)],
          distanceKm: 4,
          estimatedMinutes: 5,
          route: second,
        ),
      ],
      totalMinutes: 137,
      windingMinutes: 125,
      transitMinutes: 2,
      restMinutes: 10,
      waypoints: [LatLng(0, 1), LatLng(0, 4)],
    );

    expect(windingRouteCount(splitPlan), 2);
    expect(activeWindingRouteNumber(splitPlan, 0.25), 1);
    expect(activeWindingRouteNumber(splitPlan, 0.9), 2);
  });
}

Matcher samePoint(LatLng expected) => predicate<LatLng>(
  (actual) => actual.lat == expected.lat && actual.lng == expected.lng,
);

import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/models/drive_plan.dart';
import 'package:revv_app/models/revv_route.dart';

void main() {
  test('DrivePlan serialization round trips transit and winding legs', () {
    final route = _route();
    final plan = DrivePlan(
      legs: [
        const DrivePlanLeg(
          kind: DrivePlanLegKind.transit,
          nodes: [LatLng(45.0, -73.0), LatLng(45.1, -73.1)],
          distanceKm: 14.2,
          estimatedMinutes: 17,
        ),
        DrivePlanLeg(
          kind: DrivePlanLegKind.winding,
          nodes: route.nodes,
          distanceKm: route.distanceKm,
          estimatedMinutes: 20,
          route: route,
        ),
      ],
      totalMinutes: 37,
      windingMinutes: 20,
      transitMinutes: 17,
      waypoints: const [LatLng(45.0, -73.0), LatLng(45.2, -73.2)],
      budgetShortfallMinutes: 5,
      usesApproximateTransit: true,
    );

    final decoded = DrivePlan.fromJson(plan.toJson());

    expect(decoded.totalMinutes, 37);
    expect(decoded.windingMinutes, 20);
    expect(decoded.transitMinutes, 17);
    expect(decoded.budgetShortfallMinutes, 5);
    expect(decoded.usesApproximateTransit, isTrue);
    expect(decoded.legs.first.kind, DrivePlanLegKind.transit);
    expect(decoded.legs.last.route?.id, 'ridge');
    expect(decoded.waypoints.last.lng, -73.2);
  });
}

RevvRoute _route() {
  return const RevvRoute(
    id: 'ridge',
    name: 'Ridge Road',
    nodes: [LatLng(45.1, -73.1), LatLng(45.2, -73.2)],
    distanceKm: 16,
    windingScore: 7.2,
    starRating: 4,
    sharpCurveCount: 10,
    centerPoint: LatLng(45.15, -73.15),
    distanceFromUser: 8,
    tightCurveKm: 2.0,
    mediumCurveKm: 2.5,
    maxContinuousKm: 1.5,
  );
}

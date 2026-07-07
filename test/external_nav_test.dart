import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/models/drive_plan.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/services/external_nav.dart';

void main() {
  test('planner handoff keeps entry two key waypoints and exit in order', () {
    final points = selectHandoffWaypoints(
      legs: [
        _windingLeg([
          const LatLng(0, 0),
          const LatLng(0, 1),
          const LatLng(0, 2),
        ]),
        _windingLeg([
          const LatLng(0, 3),
          const LatLng(0, 4),
          const LatLng(0, 5),
        ]),
        _windingLeg([
          const LatLng(0, 6),
          const LatLng(0, 7),
          const LatLng(0, 8),
        ]),
      ],
    );

    expect(points, hasLength(lessThanOrEqualTo(4)));
    expect(points.map((point) => point.lng), [0, 1, 4, 8]);
  });

  test(
    'single route handoff is capped at entry two middle points and exit',
    () {
      final points = selectRouteHandoffPoints(
        List.generate(12, (index) => LatLng(45.0 + index, -73.0 - index)),
      );

      expect(points, hasLength(lessThanOrEqualTo(4)));
      expect(points.first.lat, 45.0);
      expect(points.last.lat, 56.0);
    },
  );
}

DrivePlanLeg _windingLeg(List<LatLng> nodes) {
  return DrivePlanLeg(
    kind: DrivePlanLegKind.winding,
    nodes: nodes,
    distanceKm: 1,
    estimatedMinutes: 1,
  );
}

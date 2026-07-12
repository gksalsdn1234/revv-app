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

  test('waypoints avoid hairpin apexes and snap to straighter nodes', () {
    // 직선(위도 0) 위 12개 노드, 1/3 앵커(인덱스 4)에 헤어핀 꼭짓점을 심는다.
    final nodes = [
      for (var i = 0; i < 12; i++)
        i == 4 ? const LatLng(0.6, 4) : LatLng(0, i.toDouble()),
    ];

    final points = selectRouteHandoffPoints(nodes);

    // 경유지가 꼭짓점(0.6, 4)이 아니라 주변 직선 노드로 옮겨 찍혀야 한다.
    final middles = points.sublist(1, points.length - 1);
    expect(middles, isNotEmpty);
    expect(middles.every((p) => p.lat == 0), isTrue);
  });

  test('smoothest index keeps the anchor on a fully straight polyline', () {
    final straight = [for (var i = 0; i < 12; i++) LatLng(0, i.toDouble())];

    expect(smoothestIndexNear(straight, 4), 4);
    expect(smoothestIndexNear(straight, 8), 8);
  });
}

DrivePlanLeg _windingLeg(List<LatLng> nodes) {
  return DrivePlanLeg(
    kind: DrivePlanLegKind.winding,
    nodes: nodes,
    distanceKm: 1,
    estimatedMinutes: 1,
  );
}

import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/ui/route_drive_cue.dart';

const _routeNodes = [
  LatLng(45.0000, -73.0000),
  LatLng(45.0010, -73.0000),
  LatLng(45.0010, -72.9985),
  LatLng(45.0024, -72.9985),
  LatLng(45.0024, -72.9970),
];

void main() {
  test('far before route start asks driver to reach the start point', () {
    final state = readDriveRouteState(
      const LatLng(44.9950, -73.0000),
      _routeNodes,
    );

    expect(state.status, DriveRouteStatus.approachingStart);
    expect(state.progress, 0);
    expect(state.cue?.label, '시작점까지 이동');
  });

  test('on-route state exposes the next meaningful curve within 30-800m', () {
    final state = readDriveRouteState(
      const LatLng(45.00035, -73.0000),
      _routeNodes,
    );

    expect(state.status, DriveRouteStatus.onRoute);
    expect(state.cue, isNotNull);
    expect(state.cue!.distanceM, inInclusiveRange(30, 800));
    expect(state.cue!.label, anyOf(contains('커브'), contains('헤어핀')));
  });

  test(
    'off-route state is explicit after the driver leaves the route line',
    () {
      final state = readDriveRouteState(
        const LatLng(45.0044, -72.9977),
        _routeNodes,
      );

      expect(state.status, DriveRouteStatus.offRoute);
      expect(state.cue?.label, '루트에서 벗어남');
      expect(state.distanceFromRouteM, greaterThan(120));
    },
  );

  test('near route end is treated as completed', () {
    final state = readDriveRouteState(
      const LatLng(45.0024, -72.99705),
      _routeNodes,
    );

    expect(state.status, DriveRouteStatus.completed);
    expect(state.remainingKm, lessThan(0.05));
    expect(state.cue?.label, '루트 마무리');
  });
}

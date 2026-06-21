import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/ui/drive_corner_state_machine.dart';
import 'package:revv_app/ui/route_corner_profile.dart';

const _technicalSequenceNodes = [
  LatLng(45.0000, -73.0000),
  LatLng(45.0010, -73.0000),
  LatLng(45.0010, -72.9992),
  LatLng(45.0017, -72.9992),
  LatLng(45.0017, -72.9984),
  LatLng(45.0027, -72.9984),
];

const _longApproachNodes = [
  LatLng(45.0000, -73.0000),
  LatLng(45.0055, -73.0000),
  LatLng(45.0055, -72.9990),
  LatLng(45.0061, -72.9990),
];

void main() {
  test('corner profile precomputes ordered corners with sequence metadata', () {
    final profile = RouteCornerProfile.fromNodes(_technicalSequenceNodes);

    expect(profile.totalM, greaterThan(350));
    expect(profile.corners, hasLength(greaterThanOrEqualTo(3)));

    final first = profile.corners.first;
    expect(first.nodeIndex, 1);
    expect(first.alongM, inInclusiveRange(100, 120));
    expect(first.turnDegrees, greaterThan(40));
    expect(first.type, RouteCornerType.chicane);
    expect(first.sequenceCount, greaterThanOrEqualTo(3));
    expect(first.nextGapM, isNotNull);
    expect(first.nextGapM!, lessThan(120));
  });

  test(
    'corner state machine exposes ETA-based upcoming armed active phases',
    () {
      final profile = RouteCornerProfile.fromNodes(_technicalSequenceNodes);
      final first = profile.corners.first;
      final machine = DriveCornerStateMachine(profile);

      final upcoming = machine.read(alongM: first.alongM - 230, speedKmh: 100);
      expect(upcoming.corner?.nodeIndex, first.nodeIndex);
      expect(upcoming.phase, DriveCornerPhase.upcoming);
      expect(upcoming.etaSeconds, closeTo(8.3, 0.8));

      final armed = machine.read(alongM: first.alongM - 90, speedKmh: 80);
      expect(armed.corner?.nodeIndex, first.nodeIndex);
      expect(armed.phase, DriveCornerPhase.armed);

      final active = machine.read(alongM: first.alongM - 8, speedKmh: 35);
      expect(active.corner?.nodeIndex, first.nodeIndex);
      expect(active.phase, DriveCornerPhase.active);

      final justPassed = machine.read(alongM: first.alongM + 8, speedKmh: 35);
      expect(justPassed.corner?.nodeIndex, first.nodeIndex);
      expect(justPassed.phase, DriveCornerPhase.passed);

      final afterFirst = machine.read(alongM: first.alongM + 45, speedKmh: 35);
      expect(afterFirst.corner?.nodeIndex, isNot(first.nodeIndex));
      expect(afterFirst.phase, isNot(DriveCornerPhase.passed));
    },
  );

  test('corner state machine previews fast long approaches by ETA', () {
    final profile = RouteCornerProfile.fromNodes(_longApproachNodes);
    final first = profile.corners.first;
    final machine = DriveCornerStateMachine(profile);

    final fastApproach = machine.read(
      alongM: first.alongM - 550,
      speedKmh: 180,
    );
    expect(fastApproach.corner?.nodeIndex, first.nodeIndex);
    expect(fastApproach.phase, DriveCornerPhase.upcoming);
    expect(fastApproach.distanceM, closeTo(550, 1));
    expect(fastApproach.etaSeconds, closeTo(11, 0.5));

    final slowApproach = machine.read(alongM: first.alongM - 550, speedKmh: 60);
    expect(slowApproach.phase, DriveCornerPhase.clear);
  });
}

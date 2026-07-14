import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/screens/lean_drive_screen.dart';
import 'package:revv_app/ui/route_drive_cue.dart';

void main() {
  test('completed route displays zero remaining distance', () {
    final remainingKm = driveRemainingKmForDisplay(
      remainingKm: 0,
      totalKm: 6.4,
      status: DriveRouteStatus.completed,
    );

    expect(remainingKm, 0);
  });

  test('unstarted route displays its total distance', () {
    final remainingKm = driveRemainingKmForDisplay(
      remainingKm: 0,
      totalKm: 6.4,
      status: DriveRouteStatus.approachingStart,
    );

    expect(remainingKm, 6.4);
  });
}

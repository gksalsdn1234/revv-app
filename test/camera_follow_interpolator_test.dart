import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/services/camera_follow_interpolator.dart';

void main() {
  test('interpolates halfway between fixes using the measured interval', () {
    final interpolator = CameraFollowInterpolator();
    interpolator.retarget(target: const LatLng(0, 0), now: Duration.zero);
    expect(interpolator.sample(Duration.zero)?.center, const LatLng(0, 0));
    interpolator.retarget(
      target: const LatLng(10, 20),
      now: const Duration(seconds: 1),
    );

    final frame = interpolator.sample(const Duration(milliseconds: 1500));
    expect(frame?.center.lat, closeTo(5, 0.000001));
    expect(frame?.center.lng, closeTo(10, 0.000001));
  });

  test('retargets from the current interpolated point without a jump', () {
    final interpolator = CameraFollowInterpolator();
    interpolator.retarget(target: const LatLng(0, 0), now: Duration.zero);
    interpolator.sample(Duration.zero);
    interpolator.retarget(
      target: const LatLng(10, 10),
      now: const Duration(seconds: 1),
    );
    final before = interpolator.sample(const Duration(milliseconds: 1300));

    interpolator.retarget(
      target: const LatLng(20, 20),
      now: const Duration(milliseconds: 1300),
    );
    final after = interpolator.sample(const Duration(milliseconds: 1300));

    expect(after?.center.lat, closeTo(before!.center.lat, 0.000001));
    expect(after?.center.lng, closeTo(before.center.lng, 0.000001));
  });

  test('interpolates bearing over the shortest arc', () {
    final interpolator = CameraFollowInterpolator();
    interpolator.retarget(
      target: const LatLng(0, 0),
      targetBearing: 350,
      now: Duration.zero,
    );
    interpolator.sample(Duration.zero);
    interpolator.retarget(
      target: const LatLng(1, 1),
      targetBearing: 10,
      now: const Duration(seconds: 1),
    );

    final frame = interpolator.sample(const Duration(milliseconds: 1500));
    expect(frame?.bearing, closeTo(0, 0.000001));
    expect((frame!.bearing! - 180).abs(), greaterThan(170));
  });

  test('clamps a late fix interval to 1500ms', () {
    final interpolator = CameraFollowInterpolator();
    interpolator.retarget(target: const LatLng(0, 0), now: Duration.zero);
    interpolator.sample(Duration.zero);
    interpolator.retarget(
      target: const LatLng(15, 30),
      now: const Duration(seconds: 3),
    );

    final frame = interpolator.sample(const Duration(milliseconds: 3750));
    expect(frame?.center.lat, closeTo(7.5, 0.000001));
    expect(frame?.center.lng, closeTo(15, 0.000001));
    expect(
      interpolator.sample(const Duration(milliseconds: 4500))?.center,
      const LatLng(15, 30),
    );
    expect(interpolator.sample(const Duration(milliseconds: 4501)), isNull);
  });

  test('clamps a rapid fix interval to 300ms', () {
    final interpolator = CameraFollowInterpolator();
    interpolator.retarget(target: const LatLng(0, 0), now: Duration.zero);
    interpolator.sample(Duration.zero);
    interpolator.retarget(
      target: const LatLng(3, 6),
      now: const Duration(milliseconds: 100),
    );

    final frame = interpolator.sample(const Duration(milliseconds: 250));
    expect(frame?.center.lat, closeTo(1.5, 0.000001));
    expect(frame?.center.lng, closeTo(3, 0.000001));
  });

  test('keeps the current bearing when a target bearing is absent', () {
    final interpolator = CameraFollowInterpolator();
    interpolator.retarget(
      target: const LatLng(0, 0),
      targetBearing: 45,
      now: Duration.zero,
    );
    interpolator.sample(Duration.zero);
    interpolator.retarget(
      target: const LatLng(1, 1),
      now: const Duration(seconds: 1),
    );

    expect(
      interpolator.sample(const Duration(milliseconds: 1500))?.bearing,
      45,
    );
  });

  test('snaps the first fix once and then becomes idle', () {
    final interpolator = CameraFollowInterpolator();
    interpolator.retarget(
      target: const LatLng(45, -73),
      targetBearing: 90,
      now: Duration.zero,
    );

    final frame = interpolator.sample(Duration.zero);
    expect(frame?.center, const LatLng(45, -73));
    expect(frame?.bearing, 90);
    expect(interpolator.sample(const Duration(milliseconds: 1)), isNull);
  });

  test('snaps the first GPS fix after an immediate camera reset', () {
    final interpolator = CameraFollowInterpolator();
    interpolator.reset(
      target: const LatLng(0, 0),
      bearing: 10,
      now: Duration.zero,
    );

    interpolator.retarget(
      target: const LatLng(5, 10),
      targetBearing: 20,
      now: const Duration(milliseconds: 100),
    );

    final frame = interpolator.sample(const Duration(milliseconds: 100));
    expect(frame?.center, const LatLng(5, 10));
    expect(frame?.bearing, 20);
    expect(interpolator.sample(const Duration(milliseconds: 101)), isNull);
  });

  test('keeps bearing after reset when the first GPS bearing is absent', () {
    final interpolator = CameraFollowInterpolator();
    interpolator.reset(
      target: const LatLng(0, 0),
      bearing: 45,
      now: Duration.zero,
    );

    interpolator.retarget(
      target: const LatLng(5, 10),
      now: const Duration(milliseconds: 100),
    );

    expect(interpolator.sample(const Duration(milliseconds: 100))?.bearing, 45);
  });
}

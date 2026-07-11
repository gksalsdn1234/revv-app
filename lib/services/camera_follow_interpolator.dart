import '../models/revv_route.dart';

class CameraFollowFrame {
  final LatLng center;
  final double? bearing;

  const CameraFollowFrame({required this.center, required this.bearing});
}

class CameraFollowInterpolator {
  static const Duration _minimumDuration = Duration(milliseconds: 300);
  static const Duration _maximumDuration = Duration(milliseconds: 1500);

  CameraFollowFrame? _start;
  CameraFollowFrame? _target;
  Duration? _startedAt;
  Duration? _lastFixAt;
  Duration _duration = Duration.zero;
  bool _snapPending = false;
  bool _completionPending = false;

  void retarget({
    required LatLng target,
    double? targetBearing,
    required Duration now,
  }) {
    final current = _frameAt(now);
    final previousFixAt = _lastFixAt;
    _lastFixAt = now;

    if (current == null || previousFixAt == null) {
      _target = CameraFollowFrame(
        center: target,
        bearing: targetBearing == null
            ? current?.bearing
            : _normalizeBearing(targetBearing),
      );
      _start = _target;
      _startedAt = now;
      _duration = Duration.zero;
      _snapPending = true;
      _completionPending = false;
      return;
    }

    final measured = now - previousFixAt;
    _duration = Duration(
      microseconds: measured.inMicroseconds.clamp(
        _minimumDuration.inMicroseconds,
        _maximumDuration.inMicroseconds,
      ),
    );
    _start = current;
    _target = CameraFollowFrame(
      center: target,
      bearing: targetBearing == null
          ? current.bearing
          : _normalizeBearing(targetBearing),
    );
    _startedAt = now;
    _snapPending = false;
    _completionPending = true;
  }

  CameraFollowFrame? sample(Duration now) {
    if (_snapPending) {
      _snapPending = false;
      return _target;
    }
    final startedAt = _startedAt;
    if (startedAt == null) return null;
    if (now >= startedAt + _duration) {
      if (!_completionPending) return null;
      _completionPending = false;
      return _target;
    }
    return _frameAt(now);
  }

  void reset({required LatLng target, double? bearing, required Duration now}) {
    final frame = CameraFollowFrame(
      center: target,
      bearing: _normalizeBearing(bearing),
    );
    _start = frame;
    _target = frame;
    _startedAt = now;
    _lastFixAt = null;
    _duration = Duration.zero;
    _snapPending = false;
    _completionPending = false;
  }

  CameraFollowFrame? _frameAt(Duration now) {
    final start = _start;
    final target = _target;
    final startedAt = _startedAt;
    if (start == null || target == null || startedAt == null) return null;
    if (_duration == Duration.zero || now >= startedAt + _duration) {
      return target;
    }

    final progress =
        (now - startedAt).inMicroseconds / _duration.inMicroseconds;
    return CameraFollowFrame(
      center: LatLng(
        start.center.lat + (target.center.lat - start.center.lat) * progress,
        start.center.lng + (target.center.lng - start.center.lng) * progress,
      ),
      bearing: _interpolateBearing(start.bearing, target.bearing, progress),
    );
  }

  static double? _interpolateBearing(
    double? start,
    double? target,
    double progress,
  ) {
    if (start == null || target == null) return target ?? start;
    final delta = ((target - start + 540) % 360) - 180;
    return _normalizeBearing(start + delta * progress);
  }

  static double? _normalizeBearing(double? bearing) {
    if (bearing == null) return null;
    return (bearing % 360 + 360) % 360;
  }
}

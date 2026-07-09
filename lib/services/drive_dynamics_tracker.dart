import 'dart:math' as math;

import '../models/run_telemetry_detail.dart';

class DriveDynamicsSummary {
  final int hardBrakeCount;
  final int harshSteerCount;
  final double smoothRatio;
  final double p95LateralG;
  final int sampleSeconds;

  const DriveDynamicsSummary({
    required this.hardBrakeCount,
    required this.harshSteerCount,
    required this.smoothRatio,
    required this.p95LateralG,
    required this.sampleSeconds,
  });

  bool get hasEvents => hardBrakeCount > 0 || harshSteerCount > 0;
}

class DriveDynamicsTracker {
  static const double hardBrakeThresholdG = -0.35;
  static const Duration hardBrakeMinDuration = Duration(milliseconds: 400);
  static const double harshSteerRateThresholdGps = 0.5;
  static const Duration harshSteerDebounce = Duration(milliseconds: 800);

  static const double _bucketWidth = 0.01;
  static const int _bucketCount = 201;

  final List<int> _lateralBuckets = List.filled(_bucketCount, 0);
  int _sampleCount = 0;
  int _totalMs = 0;
  int _smoothMs = 0;
  int _hardBrakeCount = 0;
  int _harshSteerCount = 0;
  double? _previousLateralG;
  Duration? _previousElapsed;
  Duration? _brakeStart;
  Duration? _steerDebounceUntil;
  bool _brakeCountedInStreak = false;
  bool _brakeEventActive = false;

  void addSample({
    required double lateralG,
    required double longitudinalG,
    required Duration elapsed,
  }) {
    _addLateralBucket(lateralG.abs());
    final previousElapsed = _previousElapsed;
    if (previousElapsed == null || elapsed <= previousElapsed) {
      _trackBrake(longitudinalG, elapsed);
      _previousElapsed = elapsed;
      _previousLateralG = lateralG;
      return;
    }

    final interval = elapsed - previousElapsed;
    _trackSteer(lateralG, interval, elapsed);
    _trackBrake(longitudinalG, elapsed);
    final intervalMs = interval.inMilliseconds;
    _totalMs += intervalMs;
    if (!_eventActiveAt(elapsed)) _smoothMs += intervalMs;
    _previousElapsed = elapsed;
    _previousLateralG = lateralG;
  }

  DriveDynamicsSummary summarize() {
    final smoothRatio = _totalMs == 0 ? 1.0 : _smoothMs / _totalMs;
    return DriveDynamicsSummary(
      hardBrakeCount: _hardBrakeCount,
      harshSteerCount: _harshSteerCount,
      smoothRatio: smoothRatio.clamp(0.0, 1.0),
      p95LateralG: _p95LateralG(),
      sampleSeconds: (_totalMs / 1000).round(),
    );
  }

  static DriveDynamicsSummary summarizeSamples(
    Iterable<TelemetrySample> samples,
  ) {
    final tracker = DriveDynamicsTracker();
    for (final sample in samples) {
      tracker.addSample(
        lateralG: sample.lateralG,
        longitudinalG: sample.longitudinalG,
        elapsed: Duration(milliseconds: sample.tMs),
      );
    }
    return tracker.summarize();
  }

  void _trackBrake(double longitudinalG, Duration elapsed) {
    if (longitudinalG <= hardBrakeThresholdG) {
      _brakeStart ??= elapsed;
      if (!_brakeCountedInStreak &&
          elapsed - _brakeStart! >= hardBrakeMinDuration) {
        _hardBrakeCount++;
        _brakeCountedInStreak = true;
        _brakeEventActive = true;
      }
      return;
    }
    _brakeStart = null;
    _brakeCountedInStreak = false;
    _brakeEventActive = false;
  }

  void _trackSteer(double lateralG, Duration interval, Duration elapsed) {
    final previous = _previousLateralG;
    if (previous == null || interval.inMicroseconds <= 0) return;
    final rate =
        (lateralG - previous).abs() /
        (interval.inMicroseconds / Duration.microsecondsPerSecond);
    if (rate <= harshSteerRateThresholdGps) return;
    final debounceUntil = _steerDebounceUntil;
    if (debounceUntil != null && elapsed < debounceUntil) return;
    _harshSteerCount++;
    _steerDebounceUntil = elapsed + harshSteerDebounce;
  }

  bool _eventActiveAt(Duration elapsed) {
    final brakeCandidateActive = _brakeStart != null;
    final steerActive =
        _steerDebounceUntil != null && elapsed < _steerDebounceUntil!;
    return brakeCandidateActive || _brakeEventActive || steerActive;
  }

  void _addLateralBucket(double value) {
    final index = math.min((value / _bucketWidth).round(), _bucketCount - 1);
    _lateralBuckets[index]++;
    _sampleCount++;
  }

  double _p95LateralG() {
    if (_sampleCount == 0) return 0;
    final target = (_sampleCount * 0.95).ceil();
    var seen = 0;
    for (var i = 0; i < _lateralBuckets.length; i++) {
      seen += _lateralBuckets[i];
      if (seen >= target) return i * _bucketWidth;
    }
    return (_bucketCount - 1) * _bucketWidth;
  }
}

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/models/run_session.dart';
import 'package:revv_app/models/run_telemetry_detail.dart';
import 'package:revv_app/services/imu_service.dart';

void main() {
  test('tilt while stationary stays near zero G', () {
    // Given: a tilted stationary phone with small gravity leakage.
    final resolver = GForceResolver(mountType: MountType.dashFlat);

    // When: GPS and gyro both say the car is stationary.
    final reading = resolver.resolve(const (
      acceleration: ImuVector(1.7, -2.1, 0.4),
      gyro: ImuVector(0, 0, 0),
      speedKmh: 0,
      dt: Duration(milliseconds: 20),
    ));

    // Then: stationary tilt cannot become ride G.
    expect(reading.lateralG.abs(), lessThanOrEqualTo(0.05));
    expect(reading.longitudinalG.abs(), lessThanOrEqualTo(0.05));
  });

  test('pure lateral input is not contaminated by gravity', () {
    // Given: dash-flat mounting and gravity-removed linear acceleration.
    final resolver = GForceResolver(mountType: MountType.dashFlat);

    // When: the car is moving with a pure 0.3g lateral sample.
    final reading = resolver.resolve(const (
      acceleration: ImuVector(GForceResolver.gravity * 0.3, 0, 0),
      gyro: ImuVector(0, 0, 0),
      speedKmh: 40,
      dt: Duration(milliseconds: 20),
    ));

    // Then: lateral maps cleanly and longitudinal stays neutral.
    expect(reading.lateralG, closeTo(0.3, 0.01));
    expect(reading.longitudinalG, closeTo(0, 0.01));
  });

  test('cruise trace noise stays under bound', () {
    // Given: a flat constant-speed cruise reference with small IMU jitter.
    final trace = _loadFixture('cruise_constant_speed.csv');

    // When: the trace goes through the resolver and telemetry smoothing.
    final readings = _resolveTrace(trace);
    final rawRms = _rawPlanarRms(trace);
    final smoothedRms = _smoothedPlanarRms(readings);
    final detail = _detailFromReadings('cruise-reference', trace, readings);

    // Then: cruise remains near 0G, and smoothing lowers deterministic noise.
    expect(rawRms, greaterThan(smoothedRms));
    expect(smoothedRms, lessThanOrEqualTo(0.006));
    expect(detail.analytics['p95AbsLateralG'], lessThanOrEqualTo(0.012));
  });

  test('steady corner lateral G stays in plausibility band', () {
    // Given: a synthetic steady corner centered around 0.30G lateral.
    final trace = _loadFixture('steady_corner_left.csv');

    // When: the trace goes through the resolver and telemetry smoothing.
    final readings = _resolveTrace(trace);
    final detail = _detailFromReadings('corner-reference', trace, readings);
    final meanLateralG = _mean(readings.map((r) => r.lateralG));
    final longitudinalRms = _rms(readings.map((r) => r.longitudinalG));

    // Then: lateral G is plausible for the stated maneuver, without long-G bleed.
    expect(meanLateralG, inInclusiveRange(0.28, 0.32));
    expect(longitudinalRms, lessThanOrEqualTo(0.003));
    expect(detail.analytics['p95AbsLateralG'], inInclusiveRange(0.28, 0.32));
    expect(detail.analytics['windingSamplePct'], 100);
  });

  test('stationary tilt perturbation trace resolves near zero G', () {
    // Given: stationary tilt leakage samples with GPS and gyro at rest.
    final trace = _loadFixture('stationary_tilt_perturbation.csv');

    // When: stationary gating is applied by the resolver.
    final readings = _resolveTrace(trace);

    // Then: tilt perturbation does not become ride G.
    expect(_rms(readings.map((r) => r.lateralG)), 0);
    expect(_rms(readings.map((r) => r.longitudinalG)), 0);
  });
}

class _ReferenceSample {
  final int tMs;
  final double speedKmh;
  final ImuVector acceleration;
  final ImuVector gyro;

  const _ReferenceSample({
    required this.tMs,
    required this.speedKmh,
    required this.acceleration,
    required this.gyro,
  });
}

List<_ReferenceSample> _loadFixture(String name) {
  final lines = File('test/fixtures/imu/$name').readAsLinesSync();
  return lines.skip(1).where((line) => line.trim().isNotEmpty).map((line) {
    final parts = line.split(',').map((part) => part.trim()).toList();
    if (parts.length != 8) {
      throw FormatException('Expected 8 CSV columns in $name', line);
    }
    return _ReferenceSample(
      tMs: int.parse(parts[0]),
      speedKmh: double.parse(parts[1]),
      acceleration: ImuVector(
        double.parse(parts[2]),
        double.parse(parts[3]),
        double.parse(parts[4]),
      ),
      gyro: ImuVector(
        double.parse(parts[5]),
        double.parse(parts[6]),
        double.parse(parts[7]),
      ),
    );
  }).toList();
}

List<GForceReading> _resolveTrace(List<_ReferenceSample> trace) {
  final resolver = GForceResolver(mountType: MountType.dashFlat);
  return [
    for (var i = 0; i < trace.length; i++)
      resolver.resolve((
        acceleration: trace[i].acceleration,
        gyro: trace[i].gyro,
        speedKmh: trace[i].speedKmh,
        dt: Duration(
          milliseconds: i == 0 ? 100 : trace[i].tMs - trace[i - 1].tMs,
        ),
      )),
  ];
}

RunTelemetryDetail _detailFromReadings(
  String runId,
  List<_ReferenceSample> trace,
  List<GForceReading> readings,
) {
  final start = DateTime.parse('2026-06-29T12:00:00Z');
  final samples = [
    for (var i = 0; i < trace.length; i++)
      TelemetrySample(
        tMs: trace[i].tMs,
        lat: 45.0,
        lng: -73.0,
        speedKmh: trace[i].speedKmh,
        lateralG: readings[i].lateralG,
        longitudinalG: readings[i].longitudinalG,
        driveMode: 'cruise',
      ),
  ];
  return RunTelemetryDetail.fromSession(
    runId,
    RunSession(
      startTime: start,
      endTime: start.add(Duration(milliseconds: trace.last.tMs)),
      maxSpeedKmh: trace.map((s) => s.speedKmh).reduce(math.max),
      avgSpeedKmh: _mean(trace.map((s) => s.speedKmh)),
      distanceKm: 0.1,
      gpsPath: const [],
      weatherEmoji: 'Clear',
      tempDisplay: '18C',
      weatherDesc: 'Clear',
      maxLateralG: readings.map((r) => r.lateralG.abs()).reduce(math.max),
      maxLonG: readings.map((r) => r.longitudinalG.abs()).reduce(math.max),
      telemetrySamples: samples,
    ),
  );
}

double _rawPlanarRms(List<_ReferenceSample> trace) => _rms(
  trace.map(
    (sample) =>
        math.sqrt(
          sample.acceleration.x * sample.acceleration.x +
              sample.acceleration.y * sample.acceleration.y,
        ) /
        GForceResolver.gravity,
  ),
);

double _smoothedPlanarRms(List<GForceReading> readings) {
  const window = 3;
  return _rms([
    for (var i = 0; i < readings.length; i++)
      math.sqrt(
        _mean(
                  readings
                      .sublist(math.max(0, i - window + 1), i + 1)
                      .map((r) => r.lateralG),
                ) *
                _mean(
                  readings
                      .sublist(math.max(0, i - window + 1), i + 1)
                      .map((r) => r.lateralG),
                ) +
            _mean(
                  readings
                      .sublist(math.max(0, i - window + 1), i + 1)
                      .map((r) => r.longitudinalG),
                ) *
                _mean(
                  readings
                      .sublist(math.max(0, i - window + 1), i + 1)
                      .map((r) => r.longitudinalG),
                ),
      ),
  ]);
}

double _rms(Iterable<double> values) {
  var sum = 0.0;
  var count = 0;
  for (final value in values) {
    sum += value * value;
    count++;
  }
  return count == 0 ? 0 : math.sqrt(sum / count);
}

double _mean(Iterable<double> values) {
  var sum = 0.0;
  var count = 0;
  for (final value in values) {
    sum += value;
    count++;
  }
  return count == 0 ? 0 : sum / count;
}

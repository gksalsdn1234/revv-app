part of 'run_telemetry_detail.dart';

const _gSmoothingWindowMs = 250;
const _eventSustainMs = 150;
const _brakingGThreshold = -0.30;
const _accelerationGThreshold = 0.25;
const _windingLateralGThreshold = 0.18;
const _sharpLateralGThreshold = 0.45;

typedef _TelemetryGate = bool Function(TelemetrySample sample);

typedef _TelemetryEventAnalysis = ({
  int accelerationEventCount,
  int brakingEventCount,
  int sharpEventCount,
  List<TelemetrySample> smoothedSamples,
  int windingSampleCount,
});

Map<String, dynamic>? _routeSnapshot(RevvRoute? route) {
  if (route == null) return null;
  return {
    'id': route.id,
    'name': route.name,
    'distanceKm': route.distanceKm,
    'windingScore': route.windingScore,
    'starRating': route.starRating,
    'sharpCurveCount': route.sharpCurveCount,
    'mediumCurveKm': route.mediumCurveKm,
    'tightCurveKm': route.tightCurveKm,
    'maxContinuousKm': route.maxContinuousKm,
    'flowScore': route.flowScore,
    'curveStyle': route.curveStyle,
    'routeCharacter': route.routeCharacter,
    'stopSignCount': route.stopSignCount,
    'trafficSignalCount': route.trafficSignalCount,
    'elevationDelta': route.elevationDelta,
    'isLoop': route.isLoop,
    'nodes': route.nodes
        .map((node) => {'lat': node.lat, 'lng': node.lng})
        .toList(),
  };
}

_TelemetryEventAnalysis _telemetryEventAnalysis(List<TelemetrySample> samples) {
  final smoothedSamples = _smoothedSamples(samples);
  final brakingEvents = _sustainedEventCount(samples, smoothedSamples, (
    smoothed: (s) => s.longitudinalG <= _brakingGThreshold && s.speedKmh >= 8,
    raw: (s) => s.longitudinalG <= _brakingGThreshold && s.speedKmh >= 8,
  ));
  final accelerationEvents = _sustainedEventCount(samples, smoothedSamples, (
    smoothed: (s) =>
        s.longitudinalG >= _accelerationGThreshold && s.speedKmh >= 8,
    raw: (s) => s.longitudinalG >= _accelerationGThreshold && s.speedKmh >= 8,
  ));
  final sharpEvents = _sustainedEventCount(samples, smoothedSamples, (
    smoothed: (s) =>
        s.lateralG.abs() >= _sharpLateralGThreshold && s.speedKmh >= 12,
    raw: (s) => s.lateralG.abs() >= _sharpLateralGThreshold && s.speedKmh >= 12,
  ));
  final windingSamples = smoothedSamples
      .where(
        (s) =>
            s.lateralG.abs() >= _windingLateralGThreshold && s.speedKmh >= 12,
      )
      .length;

  return (
    accelerationEventCount: accelerationEvents,
    brakingEventCount: brakingEvents,
    sharpEventCount: sharpEvents,
    smoothedSamples: smoothedSamples,
    windingSampleCount: windingSamples,
  );
}

List<TelemetrySample> _smoothedSamples(List<TelemetrySample> samples) {
  final smoothed = <TelemetrySample>[];
  var lateralSum = 0.0;
  var longitudinalSum = 0.0;
  var windowStart = 0;

  for (var i = 0; i < samples.length; i++) {
    final sample = samples[i];
    lateralSum += sample.lateralG;
    longitudinalSum += sample.longitudinalG;

    while (sample.tMs - samples[windowStart].tMs > _gSmoothingWindowMs) {
      lateralSum -= samples[windowStart].lateralG;
      longitudinalSum -= samples[windowStart].longitudinalG;
      windowStart++;
    }

    final count = i - windowStart + 1;
    smoothed.add(
      TelemetrySample(
        tMs: sample.tMs,
        lat: sample.lat,
        lng: sample.lng,
        speedKmh: sample.speedKmh,
        lateralG: lateralSum / count,
        longitudinalG: longitudinalSum / count,
        driveMode: sample.driveMode,
      ),
    );
  }
  return smoothed;
}

int _sustainedEventCount(
  List<TelemetrySample> rawSamples,
  List<TelemetrySample> smoothedSamples,
  ({_TelemetryGate smoothed, _TelemetryGate raw}) gate,
) {
  var count = 0;
  int? startMs;
  int? lastMs;
  int? rawStartMs;
  int? rawLastMs;
  final rawSupportTimes = <int>[];
  var rawSupportWindowStart = 0;

  void closeRun() {
    final start = startMs;
    final last = lastMs;
    final rawStart = rawStartMs;
    final rawLast = rawLastMs;
    final isSustained =
        start != null && last != null && last - start >= _eventSustainMs;
    final hasRawSupport =
        rawStart != null &&
        rawLast != null &&
        rawLast - rawStart >= _eventSustainMs;
    if (isSustained && hasRawSupport) {
      count++;
    }
    startMs = null;
    lastMs = null;
    rawStartMs = null;
    rawLastMs = null;
  }

  for (var i = 0; i < smoothedSamples.length; i++) {
    final rawSample = rawSamples[i];
    final smoothedSample = smoothedSamples[i];
    final hasRawSupportAtSample = gate.raw(rawSample);
    if (hasRawSupportAtSample) {
      rawSupportTimes.add(rawSample.tMs);
    }
    while (rawSupportWindowStart < rawSupportTimes.length &&
        rawSupportTimes[rawSupportWindowStart] <
            smoothedSample.tMs - _gSmoothingWindowMs) {
      rawSupportWindowStart++;
    }

    if (gate.smoothed(smoothedSample)) {
      if (startMs == null) {
        startMs = smoothedSample.tMs;
        if (rawSupportWindowStart < rawSupportTimes.length) {
          rawStartMs = rawSupportTimes[rawSupportWindowStart];
          rawLastMs = rawSupportTimes.last;
        }
      }
      lastMs = smoothedSample.tMs;
      if (hasRawSupportAtSample) {
        rawStartMs ??= rawSample.tMs;
        rawLastMs = rawSample.tMs;
      }
    } else {
      closeRun();
    }
  }
  closeRun();
  return count;
}

Map<String, int> _speedBuckets(List<TelemetrySample> samples) {
  final buckets = {'0_30': 0, '30_60': 0, '60_90': 0, '90_plus': 0};
  for (final sample in samples) {
    if (sample.speedKmh < 30) {
      buckets['0_30'] = buckets['0_30']! + 1;
    } else if (sample.speedKmh < 60) {
      buckets['30_60'] = buckets['30_60']! + 1;
    } else if (sample.speedKmh < 90) {
      buckets['60_90'] = buckets['60_90']! + 1;
    } else {
      buckets['90_plus'] = buckets['90_plus']! + 1;
    }
  }
  return buckets;
}

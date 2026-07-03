import '../models/run_session.dart';
import '../models/run_summary.dart';
import '../models/run_telemetry_detail.dart';
import 'run_report_metrics.dart';

class RunShareMetrics {
  final List<RunShareDisplayMetric> headlineStats;
  final List<RunShareDisplayMetric> rideMetrics;
  final RunShareDisplayMetric maxSpeedInternalOnly;

  const RunShareMetrics({
    required this.headlineStats,
    required this.rideMetrics,
    required this.maxSpeedInternalOnly,
  });

  List<RunShareDisplayMetric> get defaultShareMetrics => [
    ...headlineStats,
    ...rideMetrics,
  ];
}

class RunShareDisplayMetric {
  final String label;
  final String value;
  final bool internalOnly;

  const RunShareDisplayMetric({
    required this.label,
    required this.value,
    this.internalOnly = false,
  });
}

RunShareMetrics buildRunShareMetrics({
  RunSession? session,
  RunSummary? summary,
  RunTelemetryDetail? detail,
}) {
  final analytics = detail?.analytics ?? const <String, dynamic>{};
  final distanceKm = summary?.distanceKm ?? session?.distanceKm ?? 0;
  final durationDisplay =
      summary?.durationDisplay ?? session?.durationDisplay ?? '0s';
  final avgSpeedKmh =
      _metricDouble(analytics, 'avgSpeedKmh') ??
      summary?.avgSpeedKmh ??
      session?.avgSpeedKmh;
  final routeCompletionPct =
      _metricInt(analytics, 'routeCompletionPct') ??
      summary?.routeCompletionPct ??
      routeCompletionPercent(
        drivenKm: distanceKm,
        routeDistanceKm: session?.route?.distanceKm ?? summary?.routeDistanceKm,
      );
  final cornerEventCount =
      _metricInt(analytics, 'sharpEventCount') ??
      summary?.sharpCornersCount ??
      session?.sharpCorners.length ??
      0;
  final maxSpeedKmh =
      _metricDouble(analytics, 'maxSpeedKmh') ??
      summary?.maxSpeedKmh ??
      session?.maxSpeedKmh ??
      0;

  return RunShareMetrics(
    headlineStats: [
      RunShareDisplayMetric(
        label: 'Distance',
        value: '${distanceKm.toStringAsFixed(1)} km',
      ),
      RunShareDisplayMetric(label: 'Duration', value: durationDisplay),
      if (avgSpeedKmh != null && avgSpeedKmh > 0)
        RunShareDisplayMetric(
          label: 'Avg speed',
          value: '${avgSpeedKmh.round()} km/h',
        ),
    ],
    rideMetrics: [
      if (_metricInt(analytics, 'revvScore') ?? summary?.revvScore
          case final value?)
        RunShareDisplayMetric(label: 'REVV Score', value: '$value'),
      if (_metricInt(analytics, 'flowScoreDisplay') case final value?)
        RunShareDisplayMetric(label: 'Flow', value: '$value'),
      if (_metricInt(analytics, 'technicalScore') case final value?)
        RunShareDisplayMetric(label: 'Technical', value: '$value'),
      if (_metricInt(analytics, 'smoothnessScore') ?? summary?.smoothnessScore
          case final value?)
        RunShareDisplayMetric(label: 'Smoothness', value: '$value'),
      if (_metricDouble(analytics, 'windingSamplePct') ??
              summary?.windingSamplePct
          case final value?)
        RunShareDisplayMetric(label: 'Winding', value: '${value.round()}%'),
      if (cornerEventCount > 0)
        RunShareDisplayMetric(
          label: 'Corner events',
          value: '$cornerEventCount',
        ),
      if (routeCompletionPct != null)
        RunShareDisplayMetric(
          label: 'Route',
          value: '$routeCompletionPct% done',
        ),
    ],
    maxSpeedInternalOnly: RunShareDisplayMetric(
      label: 'Max speed',
      value: '${maxSpeedKmh.round()} km/h',
      internalOnly: true,
    ),
  );
}

int? _metricInt(Map<String, dynamic> analytics, String key) {
  final value = analytics[key];
  if (value is! num || !value.isFinite) return null;
  return value.round();
}

double? _metricDouble(Map<String, dynamic> analytics, String key) {
  final value = analytics[key];
  if (value is! num || !value.isFinite) return null;
  return value.toDouble();
}

import 'dart:math' as math;

import '../core/app_language.dart';
import '../models/run_session.dart';
import '../models/run_summary.dart';
import '../models/run_telemetry_detail.dart';
import 'app_copy.dart';
import 'run_share_metrics.dart';

enum ShareCardPreset { story, square, sticker }

enum ShareCardBackground { solid }

class RunShareCardContent {
  final ShareCardPreset preset;
  final ShareCardPresetInfo presetInfo;
  final String title;
  final String subtitle;
  final String routeName;
  final String dateLabel;
  final List<RunShareCardMetric> metricChips;
  final List<RunShareCardMetric> metricList;
  final List<RunSharePathPoint>? pathPreview;
  final String footer;
  final RunShareCardMetric? heroMetric;

  const RunShareCardContent({
    required this.preset,
    required this.presetInfo,
    required this.title,
    required this.subtitle,
    required this.routeName,
    required this.dateLabel,
    required this.metricChips,
    required this.metricList,
    this.pathPreview,
    required this.footer,
    this.heroMetric,
  });

  List<RunShareCardMetric> get metrics => metricChips;

  Iterable<String> get visibleText sync* {
    yield title;
    yield subtitle;
    yield routeName;
    yield dateLabel;
    if (heroMetric != null) {
      yield heroMetric!.label;
      yield heroMetric!.value;
    }
    for (final metric in metricChips) {
      yield metric.label;
      yield metric.value;
    }
    for (final metric in metricList) {
      yield metric.label;
      yield metric.value;
    }
    yield footer;
  }
}

class ShareCardPresetInfo {
  final ShareCardPreset preset;
  final String label;
  final double aspectRatio;
  final bool isCompact;
  final ShareCardBackground background;

  const ShareCardPresetInfo({
    required this.preset,
    required this.label,
    required this.aspectRatio,
    required this.isCompact,
    required this.background,
  });
}

class RunShareCardMetric {
  final String label;
  final String value;

  const RunShareCardMetric({required this.label, required this.value});
}

class RunSharePathPoint {
  final double x;
  final double y;

  const RunSharePathPoint({required this.x, required this.y});
}

RunShareCardContent buildRunShareCardContent({
  required ShareCardPreset preset,
  required RunSummary summary,
  RunTelemetryDetail? detail,
  RunSession? session,
  AppLanguage language = AppLanguage.english,
}) {
  final routeName = _safeText(
    summary.routeName,
    fallback: AppCopy.privateRoute(language),
  );
  final dateLabel = AppCopy.shareDateLabel(language, summary.date);
  final shareMetrics = buildRunShareMetrics(
    session: session,
    summary: summary,
    detail: detail,
    language: language,
  ).defaultShareMetrics;

  // Build safe metrics with source metric tracking
  final safeMetricsWithSource = <({RunShareCardMetric metric, RunShareDisplayMetric source})>[];
  for (final metric in shareMetrics) {
    if (!metric.internalOnly &&
        _isSafeText(metric.label) &&
        _isSafeText(metric.value)) {
      safeMetricsWithSource.add(
        (
          metric: RunShareCardMetric(label: metric.label, value: metric.value),
          source: metric,
        ),
      );
    }
  }

  final presetInfo = _presetInfo(preset, language);
  final chipLimit = presetInfo.isCompact ? 4 : 5;

  // Pick hero metric: cornerEvents first, then distance. Compact presets never
  // render the hero overlay, so keep every metric in the chips there instead.
  RunShareCardMetric? heroMetric;
  int heroIndex = -1;
  if (!presetInfo.isCompact) {
    for (int i = 0; i < safeMetricsWithSource.length; i++) {
      if (safeMetricsWithSource[i].source.id == 'cornerEvents') {
        heroIndex = i;
        break;
      }
    }

    if (heroIndex < 0) {
      for (int i = 0; i < safeMetricsWithSource.length; i++) {
        if (safeMetricsWithSource[i].source.id == 'distance') {
          heroIndex = i;
          break;
        }
      }
    }

    if (heroIndex >= 0) {
      heroMetric = safeMetricsWithSource[heroIndex].metric;
    }
  }

  // Build metric chips, excluding hero
  final metricChips = <RunShareCardMetric>[];
  for (int i = 0; i < safeMetricsWithSource.length; i++) {
    if (i != heroIndex) {
      metricChips.add(safeMetricsWithSource[i].metric);
    }
  }

  final safeMetrics = safeMetricsWithSource.map((x) => x.metric).toList();

  return RunShareCardContent(
    preset: preset,
    presetInfo: presetInfo,
    title: routeName,
    subtitle: _subtitle(
      detail: detail,
      routeName: routeName,
      dateLabel: dateLabel,
    ),
    routeName: routeName,
    dateLabel: dateLabel,
    metricChips: metricChips.take(chipLimit).toList(),
    metricList: safeMetrics,
    pathPreview: _pathPreview(detail: detail, session: session),
    footer: _weatherFooter(summary),
    heroMetric: heroMetric,
  );
}

ShareCardPresetInfo _presetInfo(ShareCardPreset preset, AppLanguage language) {
  return switch (preset) {
    ShareCardPreset.story => ShareCardPresetInfo(
      preset: ShareCardPreset.story,
      label: AppCopy.sharePresetStory(language),
      aspectRatio: 9 / 16,
      isCompact: false,
      background: ShareCardBackground.solid,
    ),
    ShareCardPreset.square => ShareCardPresetInfo(
      preset: ShareCardPreset.square,
      label: AppCopy.sharePresetSquare(language),
      aspectRatio: 1,
      isCompact: false,
      background: ShareCardBackground.solid,
    ),
    ShareCardPreset.sticker => ShareCardPresetInfo(
      preset: ShareCardPreset.sticker,
      label: AppCopy.sharePresetSticker(language),
      aspectRatio: 1,
      isCompact: true,
      background: ShareCardBackground.solid,
    ),
  };
}

String _subtitle({
  required RunTelemetryDetail? detail,
  required String routeName,
  required String dateLabel,
}) {
  final snapshot = detail?.routeSnapshot ?? const <String, dynamic>{};
  for (final key in const [
    'regionName',
    'areaName',
    'locality',
    'routeCharacter',
    'curveStyle',
    'qualityLabel',
    'surfaceSummary',
    'roadClassBucket',
  ]) {
    final value = snapshot[key];
    if (value is! String) continue;
    final text = _safeText(value, fallback: '');
    if (text.isEmpty || text == routeName || text == dateLabel) continue;
    return text;
  }
  return '';
}

String _weatherFooter(RunSummary summary) {
  final temp = summary.tempDisplay.trim();
  if (temp.isEmpty || temp == '-' || temp == '—') return '';
  return _safeText('${summary.weatherEmoji.trim()} $temp'.trim(), fallback: '');
}

String _safeText(String value, {required String fallback}) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || !_isSafeText(trimmed)) return fallback;
  return trimmed;
}

bool _isSafeText(String value) {
  return !_hasObdTerm(value) && !_hasPreciseCoordinate(value);
}

bool _hasObdTerm(String value) {
  return RegExp(
    r'\b(obd(?:-?ii|2)?|rpm|throttle|engine load|boost|vin|ecu)\b',
    caseSensitive: false,
  ).hasMatch(value);
}

bool _hasPreciseCoordinate(String value) {
  return RegExp(r'[-+]?\d{1,3}\.\d{4,}').hasMatch(value);
}

List<RunSharePathPoint>? _pathPreview({
  required RunTelemetryDetail? detail,
  required RunSession? session,
}) {
  final points =
      detail?.samples
          .map((sample) => _GeoPoint(sample.lat, sample.lng))
          .toList() ??
      session?.gpsPath.map((point) => _GeoPoint(point.lat, point.lng)).toList();
  if (points == null || points.length < 2) return null;

  final normalized = _normalize(points);
  return _downsample(normalized, 240);
}

List<RunSharePathPoint> _normalize(List<_GeoPoint> points) {
  var minLat = points.first.lat;
  var maxLat = points.first.lat;
  var minLng = points.first.lng;
  var maxLng = points.first.lng;
  for (final point in points.skip(1)) {
    if (point.lat < minLat) minLat = point.lat;
    if (point.lat > maxLat) maxLat = point.lat;
    if (point.lng < minLng) minLng = point.lng;
    if (point.lng > maxLng) maxLng = point.lng;
  }

  final latRange = maxLat - minLat;
  final lngRange = maxLng - minLng;

  // Convert to meters to preserve geographic aspect ratio.
  final latMeters = latRange * 111320.0;
  final midLat = (minLat + maxLat) / 2;
  final lngMeters = lngRange * 111320.0 * math.cos(midLat * math.pi / 180);
  final maxMeters = math.max(latMeters, lngMeters);

  if (maxMeters <= 0) {
    return [
      for (final _ in points) const RunSharePathPoint(x: 0.5, y: 0.5),
    ];
  }

  final xExtent = lngMeters / maxMeters;
  final yExtent = latMeters / maxMeters;

  // Shape-preserving: both axes share one meters-per-unit scale, centered in the unit square.
  return [
    for (final point in points)
      RunSharePathPoint(
        x: (0.5 +
                (lngRange == 0 ? 0 : ((point.lng - minLng) / lngRange - 0.5)) *
                    xExtent)
            .clamp(0.0, 1.0),
        y: (0.5 -
                (latRange == 0 ? 0 : ((point.lat - minLat) / latRange - 0.5)) *
                    yExtent)
            .clamp(0.0, 1.0),
      ),
  ];
}

List<RunSharePathPoint> _downsample(List<RunSharePathPoint> points, int cap) {
  if (points.length <= cap) return points;
  return [
    for (var i = 0; i < cap; i++)
      points[((points.length - 1) * i / (cap - 1)).round()],
  ];
}

class _GeoPoint {
  final double lat;
  final double lng;

  const _GeoPoint(this.lat, this.lng);
}

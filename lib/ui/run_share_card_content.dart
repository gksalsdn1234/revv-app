import '../models/run_session.dart';
import '../models/run_summary.dart';
import '../models/run_telemetry_detail.dart';
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
  });

  List<RunShareCardMetric> get metrics => metricChips;

  Iterable<String> get visibleText sync* {
    yield title;
    yield subtitle;
    yield routeName;
    yield dateLabel;
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
}) {
  final routeName = _safeText(summary.routeName, fallback: 'Private route');
  final dateLabel = _dateLabel(summary.date);
  final shareMetrics = buildRunShareMetrics(
    session: session,
    summary: summary,
    detail: detail,
  ).defaultShareMetrics;
  final safeMetrics = [
    for (final metric in shareMetrics)
      if (!metric.internalOnly &&
          _isSafeText(metric.label) &&
          _isSafeText(metric.value))
        RunShareCardMetric(label: metric.label, value: metric.value),
  ];
  final presetInfo = _presetInfo(preset);
  final chipLimit = presetInfo.isCompact ? 4 : 5;

  return RunShareCardContent(
    preset: preset,
    presetInfo: presetInfo,
    title: routeName,
    subtitle: '$dateLabel - ${_presetSubtitle(preset)}',
    routeName: routeName,
    dateLabel: dateLabel,
    metricChips: safeMetrics.take(chipLimit).toList(),
    metricList: safeMetrics,
    pathPreview: _pathPreview(detail: detail, session: session),
    footer: _safeText(
      '${summary.weatherEmoji} ${summary.tempDisplay}'.trim(),
      fallback: '',
    ),
  );
}

ShareCardPresetInfo _presetInfo(ShareCardPreset preset) {
  return switch (preset) {
    ShareCardPreset.story => const ShareCardPresetInfo(
      preset: ShareCardPreset.story,
      label: 'Story',
      aspectRatio: 9 / 16,
      isCompact: false,
      background: ShareCardBackground.solid,
    ),
    ShareCardPreset.square => const ShareCardPresetInfo(
      preset: ShareCardPreset.square,
      label: 'Square',
      aspectRatio: 1,
      isCompact: false,
      background: ShareCardBackground.solid,
    ),
    ShareCardPreset.sticker => const ShareCardPresetInfo(
      preset: ShareCardPreset.sticker,
      label: 'Sticker',
      aspectRatio: 1,
      isCompact: true,
      background: ShareCardBackground.solid,
    ),
  };
}

String _presetSubtitle(ShareCardPreset preset) {
  return switch (preset) {
    ShareCardPreset.story => 'REVV story',
    ShareCardPreset.square => 'REVV recap',
    ShareCardPreset.sticker => 'REVV sticker',
  };
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

String _dateLabel(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
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
  return [
    for (final point in points)
      RunSharePathPoint(
        x: lngRange == 0 ? 0.5 : ((point.lng - minLng) / lngRange).clamp(0, 1),
        y: latRange == 0
            ? 0.5
            : (1 - (point.lat - minLat) / latRange).clamp(0, 1),
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

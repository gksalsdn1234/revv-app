import 'dart:math' as math;

import '../core/app_language.dart';
import '../models/revv_route.dart';

enum RouteCurveKind { hairpin, switchback, sweeper, straight }

class RouteCurveMixSegment {
  final RouteCurveKind kind;
  final String label;
  final double share;

  const RouteCurveMixSegment({
    required this.kind,
    required this.label,
    required this.share,
  });
}

/// The only public-area choices allowed on the first sender release.
enum DriveInviteMeetingArea {
  oldPort,
  westIsland,
  northShore,
  easternTownships,
}

/// Sender-only state for one invite sheet. It has no persistence dependency.
class DriveInviteDraft {
  final String schedule;
  final DriveInviteMeetingArea? meetingArea;

  const DriveInviteDraft._({required this.schedule, this.meetingArea});

  factory DriveInviteDraft.forLanguage(AppLanguage language) {
    return DriveInviteDraft._(
      schedule: _defaultSchedule(language),
      meetingArea: null,
    );
  }

  DriveInviteDraft withMeetingArea(DriveInviteMeetingArea? value) {
    return DriveInviteDraft._(schedule: schedule, meetingArea: value);
  }
}

enum RouteInviteTag { loop, sweeper, switchback, elevation }

class RouteShareCardTag {
  final RouteInviteTag kind;
  final String label;

  const RouteShareCardTag._({required this.kind, required this.label});
}

/// A public, abstract route line. It is normalized to the 0–1 card space and
/// capped at [_maximumSilhouettePoints], so it retains no absolute coordinates.
/// The route shape itself is intentionally public invite-card artwork.
class RouteShareCardPathPoint {
  final double x;
  final double y;

  const RouteShareCardPathPoint({required this.x, required this.y});
}

/// The complete public data surface for a pre-drive invite card.
///
/// This type intentionally has no route ids, user location, raw geometry,
/// navigation links, drive telemetry, or mutable draft state.
class RouteShareCardContent {
  final AppLanguage language;
  final String headline;
  final String routeName;
  final String distanceLabel;
  final String durationLabel;
  final List<RouteShareCardTag> tags;
  final String schedule;
  final DriveInviteMeetingArea? meetingArea;
  final String? meetingAreaLabel;
  final List<RouteShareCardPathPoint> silhouette;
  final String footer;
  final int cornerCount;
  final String elevationLabel;
  final List<RouteCurveMixSegment> curveMix;

  const RouteShareCardContent._({
    required this.language,
    required this.headline,
    required this.routeName,
    required this.distanceLabel,
    required this.durationLabel,
    required this.tags,
    required this.schedule,
    required this.meetingArea,
    required this.meetingAreaLabel,
    required this.silhouette,
    required this.footer,
    required this.cornerCount,
    required this.elevationLabel,
    required this.curveMix,
  });

  Iterable<String> get visibleText sync* {
    yield headline;
    yield routeName;
    yield distanceLabel;
    yield durationLabel;
    for (final tag in tags) {
      yield tag.label;
    }
    yield schedule;
    if (meetingAreaLabel case final areaLabel?) {
      yield areaLabel;
    }
    if (cornerCount > 0) {
      yield '$cornerCount';
    }
    if (elevationLabel.isNotEmpty) {
      yield elevationLabel;
    }
    for (final segment in curveMix) {
      yield segment.label;
      yield '${(segment.share * 100).round()}%';
    }
    yield footer;
  }
}

RouteShareCardContent buildRouteShareCardContent({
  required RevvRoute route,
  DriveInviteDraft? draft,
  AppLanguage language = AppLanguage.english,
}) {
  final inviteDraft = draft ?? DriveInviteDraft.forLanguage(language);
  final elevationStr =
      route.elevationDelta > 0 ? '${route.elevationDelta.round()} m' : '';
  return RouteShareCardContent._(
    language: language,
    headline: _headline(language),
    routeName: _neutralRouteTitle(language),
    distanceLabel: _distanceLabel(route.distanceKm),
    durationLabel: _modeledDuration(route.distanceKm),
    tags: List.unmodifiable(_tagsFor(route, language).take(2)),
    schedule: inviteDraft.schedule,
    meetingArea: inviteDraft.meetingArea,
    meetingAreaLabel: _meetingAreaLabel(inviteDraft.meetingArea, language),
    silhouette: List.unmodifiable(_normalizedSilhouette(route.nodes)),
    footer: 'REVV',
    cornerCount: route.sharpCurveCount,
    elevationLabel: elevationStr,
    curveMix: List.unmodifiable(_computeCurveMix(route.nodes, language)),
  );
}

String _defaultSchedule(AppLanguage language) {
  return switch (language) {
    AppLanguage.korean => '이번 주말 · 시간 미정',
    AppLanguage.english => 'This weekend · time TBD',
    AppLanguage.french => 'Ce week-end · heure à confirmer',
  };
}

String _headline(AppLanguage language) {
  return switch (language) {
    AppLanguage.korean => '이번 주말 같이 갈래?',
    AppLanguage.english => 'Drive together this weekend?',
    AppLanguage.french => 'On roule ensemble ce week-end ?',
  };
}

/// Sender v1 never publishes [RevvRoute.name] or road names. A future route
/// title policy may opt in only to a separately vetted, non-location source.
String _neutralRouteTitle(AppLanguage language) {
  return switch (language) {
    AppLanguage.korean => 'REVV 루트',
    AppLanguage.english => 'REVV route',
    AppLanguage.french => 'Itinéraire REVV',
  };
}

String? _meetingAreaLabel(DriveInviteMeetingArea? area, AppLanguage language) {
  if (area == null) return null;
  return switch ((area, language)) {
    (DriveInviteMeetingArea.oldPort, AppLanguage.korean) => '올드 포트 근처',
    (DriveInviteMeetingArea.oldPort, AppLanguage.english) => 'Near Old Port',
    (DriveInviteMeetingArea.oldPort, AppLanguage.french) =>
      'Près du Vieux-Port',
    (DriveInviteMeetingArea.westIsland, AppLanguage.korean) => '웨스트 아일랜드',
    (DriveInviteMeetingArea.westIsland, AppLanguage.english) => 'West Island',
    (DriveInviteMeetingArea.westIsland, AppLanguage.french) => 'Ouest-de-l’Île',
    (DriveInviteMeetingArea.northShore, AppLanguage.korean) => '노스 쇼어',
    (DriveInviteMeetingArea.northShore, AppLanguage.english) => 'North Shore',
    (DriveInviteMeetingArea.northShore, AppLanguage.french) => 'Rive-Nord',
    (DriveInviteMeetingArea.easternTownships, AppLanguage.korean) => '이스턴 타운십스',
    (DriveInviteMeetingArea.easternTownships, AppLanguage.english) =>
      'Eastern Townships',
    (DriveInviteMeetingArea.easternTownships, AppLanguage.french) =>
      'Cantons-de-l’Est',
  };
}

String _distanceLabel(double distanceKm) {
  final safeDistance = distanceKm.isFinite && distanceKm > 0 ? distanceKm : 0;
  return '${safeDistance.toStringAsFixed(0)} km';
}

String _modeledDuration(double distanceKm) {
  final minutes = (distanceKm.isFinite && distanceKm > 0 ? distanceKm : 0)
      .round();
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  if (hours == 0) return '${remainder}m';
  return '${hours}h ${remainder.toString().padLeft(2, '0')}m';
}

List<RouteShareCardTag> _tagsFor(RevvRoute route, AppLanguage language) {
  final tags = <RouteInviteTag>[
    if (route.isLoop) RouteInviteTag.loop,
    if (route.curveStyle == 'SWEEPER' && route.mediumCurveKm >= 0.8)
      RouteInviteTag.sweeper,
    if (route.curveStyle == 'SWITCHBACK' && route.tightCurveKm >= 0.8)
      RouteInviteTag.switchback,
    if (route.elevationDelta >= 45) RouteInviteTag.elevation,
  ];
  return [
    for (final tag in tags)
      RouteShareCardTag._(kind: tag, label: _tagLabel(tag, language)),
  ];
}

String _tagLabel(RouteInviteTag tag, AppLanguage language) {
  return switch ((tag, language)) {
    (RouteInviteTag.loop, AppLanguage.korean) => '루프',
    (RouteInviteTag.loop, AppLanguage.english) => 'Loop route',
    (RouteInviteTag.loop, AppLanguage.french) => 'Boucle',
    (RouteInviteTag.sweeper, AppLanguage.korean) => '긴 스위퍼',
    (RouteInviteTag.sweeper, AppLanguage.english) => 'Long sweepers',
    (RouteInviteTag.sweeper, AppLanguage.french) => 'Grandes courbes',
    (RouteInviteTag.switchback, AppLanguage.korean) => '스위치백',
    (RouteInviteTag.switchback, AppLanguage.english) => 'Switchbacks',
    (RouteInviteTag.switchback, AppLanguage.french) => 'Lacets',
    (RouteInviteTag.elevation, AppLanguage.korean) => '고도 변화',
    (RouteInviteTag.elevation, AppLanguage.english) => 'Elevation',
    (RouteInviteTag.elevation, AppLanguage.french) => 'Dénivelé',
  };
}

const _maximumSilhouettePoints = 120;

List<RouteShareCardPathPoint> _normalizedSilhouette(List<LatLng> nodes) {
  if (nodes.length < 2) return const [];
  final points = nodes.length <= _maximumSilhouettePoints
      ? nodes
      : [
          for (var index = 0; index < _maximumSilhouettePoints; index++)
            nodes[((nodes.length - 1) * index / (_maximumSilhouettePoints - 1))
                .round()],
        ];
  var minLat = points.first.lat;
  var maxLat = minLat;
  var minLng = points.first.lng;
  var maxLng = minLng;
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
      for (final _ in points) const RouteShareCardPathPoint(x: 0.5, y: 0.5),
    ];
  }

  final xExtent = lngMeters / maxMeters;
  final yExtent = latMeters / maxMeters;

  // Shape-preserving: both axes share one meters-per-unit scale, centered in the unit square.
  return [
    for (final point in points)
      RouteShareCardPathPoint(
        x: (0.5 +
                (lngRange == 0 ? 0 : ((point.lng - minLng) / lngRange - 0.5)) *
                    xExtent)
            .clamp(0.0, 1.0)
            .toDouble(),
        y: (0.5 -
                (latRange == 0 ? 0 : ((point.lat - minLat) / latRange - 0.5)) *
                    yExtent)
            .clamp(0.0, 1.0)
            .toDouble(),
      ),
  ];
}

/// Compute curve-mix distribution from route nodes.
/// Length-weighted classification of turns into hairpin, switchback, sweeper, straight.
List<RouteCurveMixSegment> _computeCurveMix(
  List<LatLng> nodes,
  AppLanguage language,
) {
  if (nodes.length < 3) return const [];

  // Deliberately NOT the downsampled silhouette list. Downsampling exists to
  // keep the drawn line cheap; measuring corner radius on 400 m chords would
  // flatten every real corner into a straight. Curvature is read at the source
  // resolution — it is O(n) and never leaves this function.
  final points = nodes;

  final classLengths = <RouteCurveKind, double>{
    RouteCurveKind.hairpin: 0,
    RouteCurveKind.switchback: 0,
    RouteCurveKind.sweeper: 0,
    RouteCurveKind.straight: 0,
  };

  double totalLength = 0;

  // Add leading half-segment to straight.
  final firstSegmentLength = RevvRoute.haversineKm(points[0], points[1]) * 1000 / 2;
  classLengths[RouteCurveKind.straight] = classLengths[RouteCurveKind.straight]! + firstSegmentLength;
  totalLength += firstSegmentLength;

  // Process interior vertices for turn classification.
  for (var i = 1; i < points.length - 1; i++) {
    final bearingIn = _bearingDegrees(points[i - 1], points[i]);
    final bearingOut = _bearingDegrees(points[i], points[i + 1]);

    // Compute turn angle: normalized to [0, 180].
    var turn = (bearingOut - bearingIn).abs();
    if (turn > 180) {
      turn = 360 - turn;
    }

    // Influence length: average of the two segments meeting at this vertex.
    final legIn = RevvRoute.haversineKm(points[i - 1], points[i]) * 1000;
    final legOut = RevvRoute.haversineKm(points[i], points[i + 1]) * 1000;
    final influenceLength = (legIn + legOut) / 2;

    // Classify by corner radius, not raw turn angle. A 45° bend spread over
    // kilometres is a gentle sweeper, while the same 45° inside 40 m is a
    // switchback — only radius separates them, and it stays correct no matter
    // how densely the source polyline samples the road.
    final turnRadians = turn * math.pi / 180;
    final radiusMeters = turnRadians < 0.0175 // below ~1°, treat as straight
        ? double.infinity
        : influenceLength / turnRadians;
    final kind = switch (radiusMeters) {
      < 30 => RouteCurveKind.hairpin,
      < 80 => RouteCurveKind.switchback,
      < 400 => RouteCurveKind.sweeper,
      _ => RouteCurveKind.straight,
    };

    classLengths[kind] = classLengths[kind]! + influenceLength;
    totalLength += influenceLength;
  }

  // Add trailing half-segment to straight.
  final lastSegmentLength =
      RevvRoute.haversineKm(points[points.length - 2], points[points.length - 1]) * 1000 / 2;
  classLengths[RouteCurveKind.straight] =
      classLengths[RouteCurveKind.straight]! + lastSegmentLength;
  totalLength += lastSegmentLength;

  if (totalLength <= 0) return const [];

  // Compute shares and filter out small contributions.
  final segments = <({RouteCurveKind kind, double share})>[];
  for (final kind in [RouteCurveKind.hairpin, RouteCurveKind.switchback, RouteCurveKind.sweeper, RouteCurveKind.straight]) {
    final share = classLengths[kind]! / totalLength;
    if (share >= 0.02) {
      segments.add((kind: kind, share: share));
    }
  }

  if (segments.isEmpty) return const [];

  // A route with almost no corner content has nothing to say here — a single
  // grey "100% straight" bar reads as noise, so the card drops the block
  // entirely. It also guards low-resolution polylines, where every chord is
  // too long for a corner radius to survive.
  final corneringShare = segments
      .where((s) => s.kind != RouteCurveKind.straight)
      .fold<double>(0, (sum, s) => sum + s.share);
  if (corneringShare < 0.15) return const [];

  // Renormalize shares to sum to 1.0.
  final totalShare = segments.fold<double>(0, (sum, s) => sum + s.share);
  final normalized = [
    for (final seg in segments) (kind: seg.kind, share: seg.share / totalShare),
  ];

  // Convert to labeled segments.
  return [
    for (final seg in normalized)
      RouteCurveMixSegment(
        kind: seg.kind,
        label: _curveMixLabel(seg.kind, language),
        share: seg.share,
      ),
  ];
}

/// Compute bearing in degrees from one point to another.
double _bearingDegrees(LatLng from, LatLng to) {
  final lat1 = from.lat * math.pi / 180;
  final lat2 = to.lat * math.pi / 180;
  final dLng = (to.lng - from.lng) * math.pi / 180;
  final y = math.sin(dLng) * math.cos(lat2);
  final x =
      math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

/// Static chrome labels for the card. Kept beside the curve-mix labels so all
/// card-visible strings are localized in one place.
class RouteShareCardLabels {
  final String distance;
  final String duration;
  final String corners;
  final String elevation;
  final String curveMix;
  final String meet;

  const RouteShareCardLabels({
    required this.distance,
    required this.duration,
    required this.corners,
    required this.elevation,
    required this.curveMix,
    required this.meet,
  });

  factory RouteShareCardLabels.of(AppLanguage language) {
    return switch (language) {
      AppLanguage.korean => const RouteShareCardLabels(
        distance: '거리',
        duration: '주행 시간',
        corners: '코너',
        elevation: '고도차',
        curveMix: '커브 구성',
        meet: '집결',
      ),
      AppLanguage.english => const RouteShareCardLabels(
        distance: 'Distance',
        duration: 'Duration',
        corners: 'Corners',
        elevation: 'Elev',
        curveMix: 'Curve mix',
        meet: 'Meet',
      ),
      AppLanguage.french => const RouteShareCardLabels(
        distance: 'Distance',
        duration: 'Durée',
        corners: 'Virages',
        elevation: 'Dénivelé',
        curveMix: 'Type de virages',
        meet: 'RDV',
      ),
    };
  }
}

String _curveMixLabel(RouteCurveKind kind, AppLanguage language) {
  return switch ((kind, language)) {
    (RouteCurveKind.hairpin, AppLanguage.korean) => '헤어핀',
    (RouteCurveKind.hairpin, AppLanguage.english) => 'Hairpin',
    (RouteCurveKind.hairpin, AppLanguage.french) => 'Épingle',
    (RouteCurveKind.switchback, AppLanguage.korean) => '스위치백',
    (RouteCurveKind.switchback, AppLanguage.english) => 'Switchback',
    (RouteCurveKind.switchback, AppLanguage.french) => 'Lacet',
    (RouteCurveKind.sweeper, AppLanguage.korean) => '스위퍼',
    (RouteCurveKind.sweeper, AppLanguage.english) => 'Sweeper',
    (RouteCurveKind.sweeper, AppLanguage.french) => 'Grande courbe',
    (RouteCurveKind.straight, AppLanguage.korean) => '직선',
    (RouteCurveKind.straight, AppLanguage.english) => 'Straight',
    (RouteCurveKind.straight, AppLanguage.french) => 'Droit',
  };
}

import '../core/app_language.dart';
import '../models/revv_route.dart';

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
    yield footer;
  }
}

RouteShareCardContent buildRouteShareCardContent({
  required RevvRoute route,
  DriveInviteDraft? draft,
  AppLanguage language = AppLanguage.english,
}) {
  final inviteDraft = draft ?? DriveInviteDraft.forLanguage(language);
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
  return [
    for (final point in points)
      RouteShareCardPathPoint(
        x: lngRange == 0
            ? 0.5
            : ((point.lng - minLng) / lngRange).clamp(0, 1).toDouble(),
        y: latRange == 0
            ? 0.5
            : (1 - (point.lat - minLat) / latRange).clamp(0, 1).toDouble(),
      ),
  ];
}

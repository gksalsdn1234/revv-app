import '../core/app_language.dart';
import '../models/revv_route.dart';
import '../services/external_nav.dart';
import '../services/route_loading_policy.dart';

Uri buildRouteInviteNavigationUri(RevvRoute route) {
  final points = selectRouteHandoffPoints(route.nodes);
  if (points.length < 2) {
    return buildGoogleMapsShareUri(
      origin: route.centerPoint,
      destination: route.centerPoint,
      waypoints: const [],
    );
  }
  return buildGoogleMapsShareUri(
    origin: points.first,
    destination: points.last,
    waypoints: points.sublist(1, points.length - 1),
  );
}

String buildRouteInviteText(RevvRoute route, AppLanguage language) {
  final name = routeDisplayName(route, language: language);
  final summary = _inviteSummary(route, language);
  final navigationUrl = buildRouteInviteNavigationUri(route);
  return switch (language) {
    AppLanguage.korean =>
      '이번 주말 이 루트 같이 갈래?\n\n$name\n$summary\n\nGoogle Maps에서 열기:\n$navigationUrl\n\nREVV에서 찾은 드라이브 루트',
    AppLanguage.english =>
      'Want to drive this route this weekend?\n\n$name\n$summary\n\nOpen in Google Maps:\n$navigationUrl\n\nFound with REVV',
    AppLanguage.french =>
      'On part rouler ici ce week-end ?\n\n$name\n$summary\n\nOuvrir dans Google Maps :\n$navigationUrl\n\nTrouvé avec REVV',
  };
}

String _inviteSummary(RevvRoute route, AppLanguage language) {
  final duration = route.durationDisplay;
  return switch (language) {
    AppLanguage.korean =>
      '${route.distanceDisplay} · 약 $duration · 커브 ${route.sharpCurveCount}개',
    AppLanguage.english =>
      '${route.distanceDisplay} · about $duration · ${route.sharpCurveCount} curves',
    AppLanguage.french =>
      '${route.distanceDisplay} · environ $duration · ${route.sharpCurveCount} virages',
  };
}

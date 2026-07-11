import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/core/app_language.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/ui/route_invite.dart';

void main() {
  final route = RevvRoute(
    id: 'invite-route',
    name: 'North Ridge',
    nodes: const [
      LatLng(45.0000, -73.0000),
      LatLng(45.0100, -73.0100),
      LatLng(45.0200, -73.0200),
    ],
    distanceKm: 12,
    windingScore: 6.2,
    starRating: 4,
    sharpCurveCount: 8,
    centerPoint: const LatLng(45.0100, -73.0100),
    distanceFromUser: 7.5,
  );

  test('route invite opens a public Google Maps direction URL', () {
    final uri = buildRouteInviteNavigationUri(route);

    expect(uri.scheme, 'https');
    expect(uri.host, 'www.google.com');
    expect(uri.path, '/maps/dir/');
    expect(uri.queryParameters['origin'], '45.0000,-73.0000');
    expect(uri.queryParameters['destination'], '45.0200,-73.0200');
    expect(uri.queryParameters['waypoints'], '45.0100,-73.0100');
    expect(uri.queryParameters['travelmode'], 'driving');
  });

  test('route invite copy shares route character without home distance', () {
    final text = buildRouteInviteText(route, AppLanguage.english);

    expect(text, contains('Want to drive this route this weekend?'));
    expect(text, contains('North Ridge'));
    expect(text, contains('12 km · about 12m · 8 curves'));
    expect(text, contains('https://www.google.com/maps/dir/'));
    expect(text, isNot(contains('7.5')));
  });

  test('route start distance follows the active language', () {
    expect(route.distanceFromUserDisplayFor(AppLanguage.korean), '8 km 거리');
    expect(
      route.distanceFromUserDisplayFor(AppLanguage.english),
      '8 km to start',
    );
    expect(
      route.distanceFromUserDisplayFor(AppLanguage.french),
      '8 km jusqu’au départ',
    );
  });
}

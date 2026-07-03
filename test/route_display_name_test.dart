import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/core/app_language.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/services/route_loading_policy.dart';

RevvRoute route({
  String name = '1280740167',
  List<String> roadNames = const [],
  double tightCurveKm = 2.0,
  double mediumCurveKm = 0.5,
}) {
  return RevvRoute(
    id: 'r1',
    name: name,
    nodes: const [LatLng(45.5, -73.6), LatLng(45.6, -73.7)],
    distanceKm: 6.4,
    windingScore: 5,
    starRating: 3,
    sharpCurveCount: 4,
    centerPoint: const LatLng(45.55, -73.65),
    distanceFromUser: 3,
    tightCurveKm: tightCurveKm,
    mediumCurveKm: mediumCurveKm,
    roadNames: roadNames,
  );
}

void main() {
  test('real names pass through untouched', () {
    expect(
      routeDisplayName(route(name: 'Chemin du Lac')),
      'Chemin du Lac',
    );
  });

  test('numeric OSM ids fall back to the first enriched road name', () {
    expect(
      routeDisplayName(route(roadNames: ['Route 329', 'Chemin Fierbourg'])),
      'Route 329',
    );
  });

  test('numeric road names are skipped in the fallback chain', () {
    expect(
      routeDisplayName(route(roadNames: ['984213', 'Chemin Fierbourg'])),
      'Chemin Fierbourg',
    );
  });

  test('numeric id without road names becomes style plus distance', () {
    // tight 비중 높음 → 스위치백
    expect(routeDisplayName(route()), '스위치백 코스 6.4km');
    expect(
      routeDisplayName(route(), language: AppLanguage.english),
      'Switchback run 6.4km',
    );
  });

  test('sweeper style names accordingly', () {
    expect(
      routeDisplayName(route(tightCurveKm: 0.2, mediumCurveKm: 2.4)),
      '스위퍼 코스 6.4km',
    );
  });

  test('empty names also get the fallback', () {
    expect(routeDisplayName(route(name: '  ')), '스위치백 코스 6.4km');
  });
}

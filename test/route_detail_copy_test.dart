import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/ui/route_detail_copy.dart';

RevvRoute _route({
  String id = 'route-1',
  String name = 'Route Test',
  double distanceKm = 18,
  double tightCurveKm = 0.8,
  double mediumCurveKm = 2.4,
  double maxContinuousKm = 1.6,
  int stopSignCount = 0,
  int trafficSignalCount = 0,
  String routeCharacter = 'fast_sweeper',
  String? primaryReason,
  String? cautionNote,
}) {
  return RevvRoute(
    id: id,
    name: name,
    nodes: const [LatLng(45.0, -73.0), LatLng(45.05, -73.04)],
    distanceKm: distanceKm,
    windingScore: 6.4,
    starRating: 4,
    sharpCurveCount: 9,
    centerPoint: const LatLng(45.025, -73.02),
    distanceFromUser: 8,
    tightCurveKm: tightCurveKm,
    mediumCurveKm: mediumCurveKm,
    maxContinuousKm: maxContinuousKm,
    stopSignCount: stopSignCount,
    trafficSignalCount: trafficSignalCount,
    routeCharacter: routeCharacter,
    primaryReason: primaryReason,
    cautionNote: cautionNote,
  );
}

void main() {
  test('injected primary reason and caution copy are preserved', () {
    final route = _route(
      primaryReason: '강변을 따라 긴 중속 코너가 이어지는 주입 리뷰예요.',
      cautionNote: '후반부 마을 진입에서 흐름이 잠깐 느려집니다.',
    );

    final copy = RouteDetailCopy.fromRoute(route, startDistanceKm: 3.2);

    expect(copy.heroReason, route.primaryReason);
    expect(copy.cautionLine, route.cautionNote);
    expect(copy.decisionBullets, isNot(contains(route.primaryReason)));
    expect(copy.decisionBullets, isNot(contains(route.cautionNote)));
  });

  test('decision bullets are data based and do not repeat hero copy', () {
    final route = _route(primaryReason: '커스텀 히어로 문구입니다.');

    final copy = RouteDetailCopy.fromRoute(route, startDistanceKm: 0.2);

    expect(copy.heroReason, '커스텀 히어로 문구입니다.');
    expect(copy.decisionBullets.join('\n'), contains('커브 집중 구간'));
    expect(copy.decisionBullets.join('\n'), contains('시작점'));
    expect(copy.decisionBullets, isNot(contains(copy.heroReason)));
  });

  test('different route profiles produce different detail copy', () {
    final sweeper = RouteDetailCopy.fromRoute(
      _route(id: 'sweeper', routeCharacter: 'fast_sweeper'),
    );
    final tight = RouteDetailCopy.fromRoute(
      _route(
        id: 'tight',
        routeCharacter: 'tight_technical',
        tightCurveKm: 3.0,
        mediumCurveKm: 0.4,
        maxContinuousKm: 0.7,
      ),
    );
    final stopHeavy = RouteDetailCopy.fromRoute(
      _route(
        id: 'stop-heavy',
        stopSignCount: 5,
        trafficSignalCount: 2,
        maxContinuousKm: 0.5,
      ),
    );

    expect(tight.heroReason, isNot(sweeper.heroReason));
    expect(stopHeavy.cautionLine, contains('정지 요소'));
  });
}

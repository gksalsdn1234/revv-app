import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/core/app_language.dart';
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
  String roadClassBucket = '',
  bool isMajorRoadLike = false,
  bool isBridgeLike = false,
  bool isLoop = false,
  List<String> roadNames = const [],
  String surfaceSummary = '',
  String speedLimitSummary = '',
  List<String> nearbyPoiNames = const [],
  String? primaryReason,
  String? cautionNote,
  List<double>? elevationProfile,
  List<LatLng> nodes = const [LatLng(45.0, -73.0), LatLng(45.05, -73.04)],
}) {
  return RevvRoute(
    id: id,
    name: name,
    nodes: nodes,
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
    roadClassBucket: roadClassBucket,
    isMajorRoadLike: isMajorRoadLike,
    isBridgeLike: isBridgeLike,
    isLoop: isLoop,
    routeCharacter: routeCharacter,
    roadNames: roadNames,
    surfaceSummary: surfaceSummary,
    speedLimitSummary: speedLimitSummary,
    nearbyPoiNames: nearbyPoiNames,
    primaryReason: primaryReason,
    cautionNote: cautionNote,
    elevationProfile: elevationProfile,
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

  test(
    'route geometry creates section-aware copy when nodes are available',
    () {
      final route = _route(
        name: 'Geometry Route',
        distanceKm: 10,
        nodes: const [
          LatLng(45.000, -73.000),
          LatLng(45.010, -73.000),
          LatLng(45.010, -73.012),
          LatLng(45.020, -73.012),
          LatLng(45.030, -73.012),
          LatLng(45.040, -73.020),
        ],
      );

      final copy = RouteDetailCopy.fromRoute(route);
      final body = [copy.heroReason, ...copy.decisionBullets].join('\n');

      expect(body, contains('Geometry Route'));
      expect(body, anyOf(contains('초반'), contains('중반'), contains('후반')));
      expect(body, contains('방향 전환'));
    },
  );

  test('generic injected copy yields to geometry-based route reading', () {
    final route = _route(
      name: 'Specific Shape',
      primaryReason: '좋은 와인딩 루트예요.',
      nodes: const [
        LatLng(45.000, -73.000),
        LatLng(45.010, -73.000),
        LatLng(45.010, -73.012),
        LatLng(45.020, -73.012),
        LatLng(45.020, -73.024),
        LatLng(45.030, -73.024),
      ],
    );

    final copy = RouteDetailCopy.fromRoute(route);

    expect(copy.heroReason, isNot('좋은 와인딩 루트예요.'));
    expect(copy.heroReason, contains('Specific Shape'));
    expect(copy.heroReason, contains('방향 전환'));
  });

  test('route detail copy includes road and elevation context', () {
    final route = _route(
      name: 'Context Route',
      roadClassBucket: 'rural_named',
      roadNames: const ['Chemin du Lac'],
      surfaceSummary: 'asphalt',
      speedLimitSummary: '50',
      nearbyPoiNames: const ['Belvédère du Nord'],
      elevationProfile: const [10, 48, 72, 54, 96],
      nodes: const [
        LatLng(45.000, -73.000),
        LatLng(45.010, -73.000),
        LatLng(45.010, -73.012),
        LatLng(45.020, -73.012),
        LatLng(45.030, -73.018),
      ],
    );

    final copy = RouteDetailCopy.fromRoute(route);
    final body = copy.decisionBullets.join('\n');

    expect(body, contains('외곽도로'));
    expect(body, contains('Chemin du Lac'));
    expect(body, contains('asphalt'));
    expect(body, contains('상승'));
  });

  test('road safety context overrides generic route type notes', () {
    final route = _route(
      name: 'Bridge Connector',
      isBridgeLike: true,
      routeCharacter: 'fast_sweeper',
    );

    final copy = RouteDetailCopy.fromRoute(route);

    expect(copy.decisionBullets.join('\n'), contains('브리지'));
  });

  test('route detail copy supports English and French dossier text', () {
    final route = _route(
      distanceKm: 18,
      tightCurveKm: 1.2,
      mediumCurveKm: 1.0,
      maxContinuousKm: 1.8,
    );

    final english = RouteDetailCopy.fromRoute(
      route,
      startDistanceKm: 2.5,
      language: AppLanguage.english,
    );
    final french = RouteDetailCopy.fromRoute(
      route,
      startDistanceKm: 2.5,
      language: AppLanguage.french,
    );

    expect(english.heroReason, contains('curve-focused'));
    expect(english.decisionBullets.join(' '), contains('navigate first'));
    expect(french.heroReason, contains('virages'));
    expect(french.decisionBullets.join(' '), contains('naviguer'));
  });
}

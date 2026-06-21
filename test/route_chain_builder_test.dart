import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/models/route_chain.dart';
import 'package:revv_app/services/route_chain_builder.dart';

void main() {
  test('builds a composite route with winding and connector segments', () {
    final candidates = [
      _route('a', 45.000, -73.000, distanceKm: 10, windingScore: 8.4),
      _route('b', 45.030, -72.974, distanceKm: 9, windingScore: 7.6),
      _route('c', 45.055, -72.948, distanceKm: 8, windingScore: 7.2),
    ];

    final chain = const RouteChainBuilder().buildBestForTarget(
      candidates,
      RouteChainTarget.minutes30,
      origin: candidates.first.nodes.first,
    );

    expect(chain, isNotNull);
    expect(chain!.routeLegs.length, greaterThanOrEqualTo(2));
    expect(chain.connectors, isNotEmpty);
    expect(chain.connectorRatio, lessThan(0.22));

    final composite = chain.toRevvRoute(origin: candidates.first.nodes.first);
    expect(composite.isCompositeRoute, isTrue);
    expect(composite.nodes.first, candidates.first.nodes.first);
    expect(composite.nodes.length, greaterThan(candidates.first.nodes.length));
    expect(
      composite.chainSegments.map((segment) => segment.kind),
      containsAll([RouteSegmentKind.winding, RouteSegmentKind.connector]),
    );
    expect(composite.distanceKm, closeTo(chain.totalDistanceKm, 0.001));
  });

  test('placeholder connector chains are not marked drivable', () {
    final first = _route('a', 45.000, -73.000, distanceKm: 10);
    final second = _route('b', 45.030, -72.974, distanceKm: 9);
    final firstLeg = RouteChainRouteLeg(route: first);
    final secondLeg = RouteChainRouteLeg(route: second);
    final chain = RouteChain(
      target: RouteChainTarget.minutes30,
      routeLegs: [firstLeg, secondLeg],
      connectors: [RouteConnectorLeg.between(firstLeg, secondLeg)],
    );

    expect(chain.hasDrivableConnectors, isFalse);
  });

  test('composite route merge keeps connector road geometry', () {
    final first = _route('a', 45.000, -73.000, distanceKm: 10);
    final second = _route('b', 45.030, -72.974, distanceKm: 9);
    final firstLeg = RouteChainRouteLeg(route: first);
    final secondLeg = RouteChainRouteLeg(route: second);
    final connector = RouteConnectorLeg.between(
      firstLeg,
      secondLeg,
      polyline: [firstLeg.end, const LatLng(45.027, -72.980), secondLeg.start],
      distanceKm: 1.8,
    );
    final chain = RouteChain(
      target: RouteChainTarget.minutes30,
      routeLegs: [firstLeg, secondLeg],
      connectors: [connector],
    );

    expect(chain.hasDrivableConnectors, isTrue);
    final composite = chain.toRevvRoute(origin: first.nodes.first);
    final connectorSegment = composite.chainSegments.singleWhere(
      (segment) => segment.isConnector,
    );

    expect(
      composite.nodes.any(
        (node) =>
            (node.lat - 45.027).abs() < 0.000001 &&
            (node.lng + 72.980).abs() < 0.000001,
      ),
      isTrue,
    );
    expect(
      connectorSegment.endNodeIndex - connectorSegment.startNodeIndex,
      greaterThanOrEqualTo(2),
    );
  });

  test('composite route preserves stop and risk metadata from legs', () {
    final first = _route(
      'a',
      45.000,
      -73.000,
      distanceKm: 10,
      stopSignCount: 2,
      trafficSignalCount: 1,
      isMajorRoadLike: true,
    );
    final second = _route(
      'b',
      45.030,
      -72.974,
      distanceKm: 9,
      stopSignCount: 1,
      trafficSignalCount: 2,
      isBridgeLike: true,
    );
    final firstLeg = RouteChainRouteLeg(route: first);
    final secondLeg = RouteChainRouteLeg(route: second);
    final connector = RouteConnectorLeg.between(
      firstLeg,
      secondLeg,
      polyline: [firstLeg.end, secondLeg.start],
      distanceKm: 1.8,
    );
    final chain = RouteChain(
      target: RouteChainTarget.minutes30,
      routeLegs: [firstLeg, secondLeg],
      connectors: [connector],
    );

    final composite = chain.toRevvRoute(origin: first.nodes.first);

    expect(composite.stopSignCount, 3);
    expect(composite.trafficSignalCount, 3);
    expect(composite.stopControlDensity, greaterThan(0));
    expect(composite.isMajorRoadLike, isTrue);
    expect(composite.isBridgeLike, isTrue);
    expect(composite.driveabilityPenalty, inInclusiveRange(0.05, 1.0));
  });

  test(
    'connector penalty keeps a nearby route over a far high-score route',
    () {
      final start = _route('start', 45.000, -73.000, distanceKm: 12);
      final near = _route(
        'near',
        45.034,
        -72.971,
        distanceKm: 12,
        windingScore: 7.4,
      );
      final far = _route(
        'far',
        45.700,
        -72.250,
        distanceKm: 12,
        windingScore: 9.9,
      );

      final chain = const RouteChainBuilder().buildBestForTarget(
        [start, near, far],
        RouteChainTarget.minutes30,
        origin: start.nodes.first,
      );

      expect(chain, isNotNull);
      expect(chain!.routeLegs.map((leg) => leg.route.id), contains('near'));
      expect(
        chain.routeLegs.map((leg) => leg.route.id),
        isNot(contains('far')),
      );
    },
  );

  test('target duration changes the preferred chain length', () {
    final candidates = [
      _route('a', 45.000, -73.000, distanceKm: 11),
      _route('b', 45.034, -72.971, distanceKm: 12),
      _route('c', 45.068, -72.942, distanceKm: 13),
      _route('d', 45.102, -72.913, distanceKm: 14),
      _route('e', 45.136, -72.884, distanceKm: 15),
    ];

    final builder = const RouteChainBuilder();
    final short = builder.buildBestForTarget(
      candidates,
      RouteChainTarget.minutes30,
      origin: candidates.first.nodes.first,
    );
    final long = builder.buildBestForTarget(
      candidates,
      RouteChainTarget.minutes60,
      origin: candidates.first.nodes.first,
    );

    expect(short, isNotNull);
    expect(long, isNotNull);
    expect(long!.totalDistanceKm, greaterThan(short!.totalDistanceKm));
    expect(long.targetDeltaKm, lessThan(short.targetDeltaKm + 20));
  });

  test('buildOptions hides targets that cannot be approximated', () {
    final candidates = [
      _route('a', 45.000, -73.000, distanceKm: 5),
      _route('b', 45.020, -72.980, distanceKm: 5),
    ];

    final options = const RouteChainBuilder().buildOptions(
      candidates,
      origin: candidates.first.nodes.first,
    );

    expect(
      options.map((chain) => chain.target),
      isNot(contains(RouteChainTarget.minutes90)),
    );
  });

  test(
    'buildOptionsWithConnectorGeometry returns only drivable chains',
    () async {
      final candidates = [
        _route('a', 45.000, -73.000, distanceKm: 10),
        _route('b', 45.030, -72.974, distanceKm: 9),
        _route('c', 45.055, -72.948, distanceKm: 8),
      ];

      final options = await const RouteChainBuilder()
          .buildOptionsWithConnectorGeometry(
            candidates,
            origin: candidates.first.nodes.first,
            resolveConnector: (fromLeg, toLeg) async {
              return RouteConnectorLeg.between(
                fromLeg,
                toLeg,
                polyline: [fromLeg.end, toLeg.start],
              );
            },
          );

      expect(options, isNotEmpty);
      expect(options.every((chain) => chain.hasDrivableConnectors), isTrue);
    },
  );

  test(
    'buildOptionsWithConnectorGeometry drops chains without road connectors',
    () async {
      final candidates = [
        _route('a', 45.000, -73.000, distanceKm: 10),
        _route('b', 45.030, -72.974, distanceKm: 9),
        _route('c', 45.055, -72.948, distanceKm: 8),
      ];

      final options = await const RouteChainBuilder()
          .buildOptionsWithConnectorGeometry(
            candidates,
            origin: candidates.first.nodes.first,
            resolveConnector: (fromLeg, toLeg) async => null,
          );

      expect(options, isEmpty);
    },
  );

  test('first route leg can be reversed when it improves the chain', () {
    final first = _routeWithNodes(
      'first',
      const [LatLng(45.000, -73.000), LatLng(45.060, -72.990)],
      distanceKm: 12,
      windingScore: 9.2,
      routeRankScore: 120,
    );
    final next = _routeWithNodes(
      'next',
      const [LatLng(45.002, -72.998), LatLng(45.026, -72.972)],
      distanceKm: 12,
      windingScore: 7.6,
    );

    final chain = const RouteChainBuilder().buildBestForTarget(
      [first, next],
      RouteChainTarget.minutes30,
      origin: first.nodes.last,
    );

    expect(chain, isNotNull);
    expect(chain!.routeLegs.first.route.id, 'first');
    expect(chain.routeLegs.first.reversed, isTrue);
  });

  test('similarity and backtracking penalties reduce chain score', () {
    final base = _route('base', 45.000, -73.000, distanceKm: 12);
    final duplicate = _route(
      'duplicate',
      45.006,
      -72.995,
      distanceKm: 11,
      windingScore: 8.8,
    );
    final diverse = _route(
      'diverse',
      45.045,
      -72.960,
      distanceKm: 11,
      windingScore: 7.8,
    );

    final builder = const RouteChainBuilder();
    final duplicateChain = RouteChain(
      target: RouteChainTarget.minutes30,
      routeLegs: [
        RouteChainRouteLeg(route: base),
        RouteChainRouteLeg(route: duplicate),
      ],
      connectors: [
        RouteConnectorLeg.between(
          RouteChainRouteLeg(route: base),
          RouteChainRouteLeg(route: duplicate),
        ),
      ],
    );
    final diverseChain = RouteChain(
      target: RouteChainTarget.minutes30,
      routeLegs: [
        RouteChainRouteLeg(route: base),
        RouteChainRouteLeg(route: diverse),
      ],
      connectors: [
        RouteConnectorLeg.between(
          RouteChainRouteLeg(route: base),
          RouteChainRouteLeg(route: diverse),
        ),
      ],
    );

    expect(
      builder.scoreChain(diverseChain, origin: base.nodes.first),
      greaterThan(builder.scoreChain(duplicateChain, origin: base.nodes.first)),
    );
  });
}

RevvRoute _route(
  String id,
  double lat,
  double lng, {
  double distanceKm = 10,
  double windingScore = 8,
  double routeRankScore = 0,
  int stopSignCount = 0,
  int trafficSignalCount = 0,
  bool isBridgeLike = false,
  bool isMajorRoadLike = false,
}) {
  final nodes = [
    LatLng(lat, lng),
    LatLng(lat + 0.012, lng + 0.004),
    LatLng(lat + 0.024, lng + 0.020),
  ];
  return RevvRoute(
    id: id,
    name: 'Route $id',
    nodes: nodes,
    distanceKm: distanceKm,
    windingScore: windingScore,
    starRating: RevvRoute.toStarRating(windingScore),
    sharpCurveCount: (distanceKm * 1.7).round(),
    centerPoint: nodes[1],
    distanceFromUser: 0,
    tightCurveKm: distanceKm * 0.28,
    mediumCurveKm: distanceKm * 0.36,
    routeRankScore: routeRankScore == 0 ? windingScore * 10 : routeRankScore,
    flowScore: 0.82,
    driveabilityPenalty: 0.9,
    stopSignCount: stopSignCount,
    trafficSignalCount: trafficSignalCount,
    stopControlDensity: (stopSignCount + trafficSignalCount * 1.5) / distanceKm,
    isBridgeLike: isBridgeLike,
    isMajorRoadLike: isMajorRoadLike,
  );
}

RevvRoute _routeWithNodes(
  String id,
  List<LatLng> nodes, {
  double distanceKm = 10,
  double windingScore = 8,
  double routeRankScore = 0,
}) {
  return RevvRoute(
    id: id,
    name: 'Route $id',
    nodes: nodes,
    distanceKm: distanceKm,
    windingScore: windingScore,
    starRating: RevvRoute.toStarRating(windingScore),
    sharpCurveCount: (distanceKm * 1.7).round(),
    centerPoint: nodes[nodes.length ~/ 2],
    distanceFromUser: 0,
    tightCurveKm: distanceKm * 0.28,
    mediumCurveKm: distanceKm * 0.36,
    routeRankScore: routeRankScore == 0 ? windingScore * 10 : routeRankScore,
    flowScore: 0.82,
    driveabilityPenalty: 0.9,
  );
}

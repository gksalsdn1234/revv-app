import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/models/chain_candidate.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/services/route_chain_policy.dart';

RevvRoute _route({
  required String id,
  required String name,
  required List<LatLng> nodes,
  required double distanceKm,
  required double windingScore,
  double flowScore = 0.85,
  double funScore = 7.5,
  double routeRankScore = 6.2,
  int stopSignCount = 0,
  int trafficSignalCount = 0,
  bool isConnectorLike = false,
  bool isBridgeLike = false,
  bool isMajorRoadLike = false,
}) {
  final center = LatLng(
    nodes.map((n) => n.lat).reduce((a, b) => a + b) / nodes.length,
    nodes.map((n) => n.lng).reduce((a, b) => a + b) / nodes.length,
  );
  return RevvRoute(
    id: id,
    name: name,
    nodes: nodes,
    distanceKm: distanceKm,
    windingScore: windingScore,
    starRating: 4,
    sharpCurveCount: 8,
    centerPoint: center,
    distanceFromUser: 8,
    flowScore: flowScore,
    funScore: funScore,
    routeRankScore: routeRankScore,
    stopSignCount: stopSignCount,
    trafficSignalCount: trafficSignalCount,
    isConnectorLike: isConnectorLike,
    isBridgeLike: isBridgeLike,
    isMajorRoadLike: isMajorRoadLike,
    tightCurveKm: distanceKm * 0.18,
    mediumCurveKm: distanceKm * 0.21,
    maxContinuousKm: distanceKm * 0.14,
  );
}

void main() {
  test('buildChainCandidates keeps only high quality nearby follow-up routes', () {
    final base = _route(
      id: 'base',
      name: 'North Run',
      nodes: const [
        LatLng(45.4600, -73.6400),
        LatLng(45.4700, -73.6200),
        LatLng(45.4800, -73.6000),
      ],
      distanceKm: 14,
      windingScore: 7.8,
      routeRankScore: 8.0,
    );
    final good = _route(
      id: 'good',
      name: 'Lake Sweep',
      nodes: const [
        LatLng(45.4810, -73.5980),
        LatLng(45.4950, -73.5750),
        LatLng(45.5080, -73.5520),
      ],
      distanceKm: 12,
      windingScore: 7.0,
      routeRankScore: 7.4,
    );
    final badRamp = _route(
      id: 'ramp',
      name: 'Connector Ramp',
      nodes: const [
        LatLng(45.4820, -73.6010),
        LatLng(45.4870, -73.5900),
      ],
      distanceKm: 4.8,
      windingScore: 3.4,
      routeRankScore: 2.1,
      isConnectorLike: true,
      isMajorRoadLike: true,
    );
    final farAway = _route(
      id: 'far',
      name: 'Far Route',
      nodes: const [
        LatLng(45.6100, -73.3000),
        LatLng(45.6250, -73.2700),
      ],
      distanceKm: 13,
      windingScore: 7.3,
      routeRankScore: 7.1,
    );

    final candidates = buildChainCandidates(
      baseRoute: base,
      allRoutes: [good, badRamp, farAway],
      limit: 3,
    );

    expect(candidates, hasLength(1));
    expect(candidates.first.route.id, 'good');
    expect(candidates.first.gapKm, lessThan(5));
    expect(candidates.first.mergedRankScore, greaterThan(0));
  });

  test('buildChainCandidates can reverse entry when end is the better connector', () {
    final base = _route(
      id: 'base',
      name: 'Base',
      nodes: const [
        LatLng(45.4600, -73.6400),
        LatLng(45.4700, -73.6200),
        LatLng(45.4800, -73.6000),
      ],
      distanceKm: 13,
      windingScore: 7.1,
      routeRankScore: 7.5,
    );
    final reverseBetter = _route(
      id: 'follow',
      name: 'Reverse Entry',
      nodes: const [
        LatLng(45.5200, -73.5400),
        LatLng(45.5000, -73.5650),
        LatLng(45.4820, -73.5985),
      ],
      distanceKm: 11,
      windingScore: 6.8,
      routeRankScore: 6.9,
    );

    final candidates = buildChainCandidates(
      baseRoute: base,
      allRoutes: [reverseBetter],
      limit: 3,
    );

    expect(candidates, hasLength(1));
    expect(candidates.first.entryMode, ChainEntryMode.reverse);
  });

  test('buildCompositeRoute merges route nodes with a real connector leg', () {
    final base = _route(
      id: 'base',
      name: 'Base',
      nodes: const [
        LatLng(45.4600, -73.6400),
        LatLng(45.4700, -73.6200),
        LatLng(45.4800, -73.6000),
      ],
      distanceKm: 14,
      windingScore: 7.6,
      routeRankScore: 8.2,
      stopSignCount: 1,
      trafficSignalCount: 0,
    );
    final follow = _route(
      id: 'follow',
      name: 'Follow',
      nodes: const [
        LatLng(45.4810, -73.5980),
        LatLng(45.4950, -73.5750),
        LatLng(45.5080, -73.5520),
      ],
      distanceKm: 12,
      windingScore: 6.9,
      routeRankScore: 7.0,
      stopSignCount: 2,
      trafficSignalCount: 1,
    );
    final candidate = ChainCandidate(
      route: follow,
      entryMode: ChainEntryMode.forward,
      gapKm: 0.3,
      headingDelta: 18,
      connectorQualityScore: 0.88,
      mergedFunScore: 7.4,
      mergedFlowScore: 0.79,
      mergedRankScore: 5.4,
    );

    final composite = buildCompositeRoute(
      baseRoute: base,
      candidate: candidate,
      connectorPolyline: const [
        LatLng(45.4800, -73.6000),
        LatLng(45.4805, -73.5990),
        LatLng(45.4810, -73.5980),
      ],
    );

    expect(composite.chainedSegments, hasLength(1));
    expect(composite.connectorLegs, hasLength(1));
    expect(composite.mergedNodes.length, greaterThan(base.nodes.length + follow.nodes.length - 1));
    expect(composite.totalDistanceKm, greaterThan(base.distanceKm + follow.distanceKm));
    expect(composite.routeRankScore, 5.4);
    expect(composite.stopSignCount, 3);
    expect(composite.trafficSignalCount, 1);
    expect(composite.toRouteProjection().name, contains(' + '));
  });

  test('ensureChainCandidateNodes hydrates nearby node-less routes before scoring', () async {
    final base = _route(
      id: 'base',
      name: 'Base',
      nodes: const [
        LatLng(45.4600, -73.6400),
        LatLng(45.4700, -73.6200),
        LatLng(45.4800, -73.6000),
      ],
      distanceKm: 14,
      windingScore: 7.6,
      routeRankScore: 8.2,
    );
    final unloadedNearby = RevvRoute(
      id: 'candidate',
      name: 'Candidate',
      nodes: const [],
      distanceKm: 12,
      windingScore: 6.8,
      starRating: 4,
      sharpCurveCount: 7,
      centerPoint: const LatLng(45.492, -73.575),
      distanceFromUser: 9,
      routeRankScore: 7.0,
      flowScore: 0.8,
      funScore: 7.0,
    );
    final far = RevvRoute(
      id: 'far',
      name: 'Far',
      nodes: const [],
      distanceKm: 12,
      windingScore: 6.8,
      starRating: 4,
      sharpCurveCount: 7,
      centerPoint: const LatLng(46.2, -72.1),
      distanceFromUser: 60,
      routeRankScore: 7.0,
      flowScore: 0.8,
      funScore: 7.0,
    );

    final hydrated = await ensureChainCandidateNodes(
      baseRoute: base,
      allRoutes: [unloadedNearby, far],
      loadNodes: (routeId) async {
        if (routeId == 'candidate') {
          return const [
            LatLng(45.4810, -73.5980),
            LatLng(45.4950, -73.5750),
            LatLng(45.5080, -73.5520),
          ];
        }
        fail('far route should not be hydrated');
      },
    );

    final candidate = hydrated.firstWhere((route) => route.id == 'candidate');
    expect(candidate.nodes, isNotEmpty);
  });

  test('buildCompositeRoute stores reversed segment orientation when reverse entry is chosen', () {
    final base = _route(
      id: 'base',
      name: 'Base',
      nodes: const [
        LatLng(45.4600, -73.6400),
        LatLng(45.4700, -73.6200),
        LatLng(45.4800, -73.6000),
      ],
      distanceKm: 14,
      windingScore: 7.6,
      routeRankScore: 8.2,
    );
    final follow = _route(
      id: 'follow',
      name: 'Reverse Entry',
      nodes: const [
        LatLng(45.5200, -73.5400),
        LatLng(45.5000, -73.5650),
        LatLng(45.4820, -73.5985),
      ],
      distanceKm: 11,
      windingScore: 6.8,
      routeRankScore: 6.9,
    );
    final candidate = ChainCandidate(
      route: follow,
      entryMode: ChainEntryMode.reverse,
      gapKm: 0.3,
      headingDelta: 18,
      connectorQualityScore: 0.88,
      mergedFunScore: 7.4,
      mergedFlowScore: 0.79,
      mergedRankScore: 5.4,
    );

    final composite = buildCompositeRoute(
      baseRoute: base,
      candidate: candidate,
      connectorPolyline: const [
        LatLng(45.4800, -73.6000),
        LatLng(45.4808, -73.5990),
        LatLng(45.4820, -73.5985),
      ],
    );

    expect(composite.chainedSegments.single.id, 'follow');
    expect(composite.chainedSegments.single.nodes.first.lat, closeTo(45.4820, 0.00001));
    expect(composite.chainedSegments.single.nodes.last.lat, closeTo(45.5200, 0.00001));
  });
}

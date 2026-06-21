import 'dart:math' as math;

import '../models/revv_route.dart';
import '../models/route_chain.dart';

typedef RouteConnectorResolver =
    Future<RouteConnectorLeg?> Function(
      RouteChainRouteLeg fromLeg,
      RouteChainRouteLeg toLeg,
    );

class RouteChainBuilder {
  final int maxCandidatePool;
  final int maxRouteLegs;
  final int beamWidth;

  const RouteChainBuilder({
    this.maxCandidatePool = 18,
    this.maxRouteLegs = 5,
    this.beamWidth = 18,
  });

  List<RouteChain> buildOptions(List<RevvRoute> candidates, {LatLng? origin}) {
    return RouteChainTarget.values
        .map((target) => buildBestForTarget(candidates, target, origin: origin))
        .whereType<RouteChain>()
        .toList(growable: false);
  }

  Future<List<RouteChain>> buildOptionsWithConnectorGeometry(
    List<RevvRoute> candidates, {
    LatLng? origin,
    required RouteConnectorResolver resolveConnector,
  }) async {
    final options = <RouteChain>[];
    for (final target in RouteChainTarget.values) {
      final ranked = buildRankedForTarget(
        candidates,
        target,
        origin: origin,
        limit: 6,
      );
      for (final candidate in ranked) {
        final hydrated = await _hydrateConnectors(
          candidate,
          resolveConnector: resolveConnector,
          origin: origin,
        );
        if (hydrated == null || !hydrated.hasDrivableConnectors) continue;
        if (!_isTargetAcceptable(hydrated)) continue;
        options.add(hydrated);
        break;
      }
    }
    return options;
  }

  RouteChain? buildBestForTarget(
    List<RevvRoute> candidates,
    RouteChainTarget target, {
    LatLng? origin,
  }) {
    final ranked = buildRankedForTarget(candidates, target, origin: origin);
    return ranked.isEmpty ? null : ranked.first;
  }

  List<RouteChain> buildRankedForTarget(
    List<RevvRoute> candidates,
    RouteChainTarget target, {
    LatLng? origin,
    int limit = 1,
  }) {
    final pool = _candidatePool(candidates, origin: origin);
    if (pool.length < 2) return const [];

    var states = pool
        .take(math.min(pool.length, 10))
        .expand(
          (route) => _seedLegs(route).map(
            (leg) => RouteChain(
              target: target,
              routeLegs: [leg],
              connectors: const [],
            ),
          ),
        )
        .toList();

    for (var depth = 1; depth < maxRouteLegs; depth++) {
      final expanded = <RouteChain>[...states];
      for (final state in states) {
        if (state.totalDistanceKm >= target.targetDistanceKm * 1.18) continue;
        for (final candidate in pool) {
          if (state.routeLegs.any((leg) => leg.route.id == candidate.id)) {
            continue;
          }
          final nextLeg = _bestLegFrom(state.routeLegs.last.end, candidate);
          final connector = RouteConnectorLeg.between(
            state.routeLegs.last,
            nextLeg,
          );
          if (!_isConnectorUsable(connector, target, candidate)) continue;
          final next = RouteChain(
            target: target,
            routeLegs: [...state.routeLegs, nextLeg],
            connectors: [...state.connectors, connector],
          );
          expanded.add(next.copyWith(score: scoreChain(next, origin: origin)));
        }
      }
      expanded.sort((a, b) {
        final scoreCompare = b.score.compareTo(a.score);
        if (scoreCompare != 0) return scoreCompare;
        return a.targetDeltaKm.compareTo(b.targetDeltaKm);
      });
      states = expanded.take(beamWidth).toList(growable: false);
    }

    final eligible = states
        .where((chain) => chain.routeLegs.length >= 2)
        .map(
          (chain) => chain.copyWith(score: scoreChain(chain, origin: origin)),
        )
        .toList();
    eligible.removeWhere((chain) => !_isTargetAcceptable(chain));
    if (eligible.isEmpty) return const [];
    eligible.sort((a, b) => b.score.compareTo(a.score));
    return eligible.take(limit).toList(growable: false);
  }

  double scoreChain(RouteChain chain, {LatLng? origin}) {
    final routeKm = chain.routeDistanceKm;
    final totalKm = chain.totalDistanceKm;
    if (routeKm <= 0 || totalKm <= 0) return double.negativeInfinity;

    final weightedWinding =
        chain.routeLegs.fold(
          0.0,
          (total, leg) =>
              total +
              leg.route.windingScore * math.max(0.0, leg.route.distanceKm),
        ) /
        routeKm;
    final sharpCurveCount = chain.routeLegs.fold(
      0,
      (total, leg) => total + leg.route.sharpCurveCount,
    );
    final cornerDensity = sharpCurveCount / math.max(1.0, routeKm);
    final targetFit = _targetFit(totalKm, chain.target.targetDistanceKm);
    final connectorPenalty = _connectorPenalty(chain);
    final backtrackingPenalty = _backtrackingPenalty(chain, origin);
    final similarityPenalty = _similarityPenalty(chain.routeLegs);
    final legBonus = math.min(3, chain.routeLegs.length - 1) * 2.5;

    var score =
        weightedWinding * 6.2 +
        math.min(8.0, cornerDensity) * 2.4 +
        targetFit * 24 +
        legBonus -
        connectorPenalty -
        backtrackingPenalty -
        similarityPenalty;
    if (chain.routeLegs.length < 2) score -= 30;
    if (chain.connectorRatio > 0.45) {
      score -= (chain.connectorRatio - 0.45) * 70;
    }
    return score;
  }

  List<RevvRoute> _candidatePool(List<RevvRoute> candidates, {LatLng? origin}) {
    final unique = <String, RevvRoute>{};
    for (final route in candidates) {
      if (route.nodes.length < 2 || route.distanceKm <= 0.8) continue;
      if (route.isConnectorLike ||
          route.isFacilityLike ||
          route.isPrivateLike) {
        continue;
      }
      unique[route.id] = route;
    }
    final scored = unique.values.toList()
      ..sort((a, b) => _seedScore(b, origin).compareTo(_seedScore(a, origin)));
    return scored.take(maxCandidatePool).toList(growable: false);
  }

  List<RouteChainRouteLeg> _seedLegs(RevvRoute route) {
    if (route.nodes.length < 2) return const [];
    return [
      RouteChainRouteLeg(route: route),
      RouteChainRouteLeg(route: route, reversed: true),
    ];
  }

  double _seedScore(RevvRoute route, LatLng? origin) {
    final density = route.sharpCurveCount / math.max(1.0, route.distanceKm);
    final distancePenalty = origin == null
        ? 0.0
        : math.min(
            12.0,
            RevvRoute.haversineKm(origin, route.nodes.first) * 0.08,
          );
    return route.windingScore * 8 +
        density * 2.5 +
        route.routeRankScore * 0.03 -
        distancePenalty;
  }

  RouteChainRouteLeg _bestLegFrom(LatLng from, RevvRoute route) {
    final normal = RevvRoute.haversineKm(from, route.nodes.first);
    final reversed = RevvRoute.haversineKm(from, route.nodes.last);
    return RouteChainRouteLeg(route: route, reversed: reversed < normal);
  }

  bool _isConnectorUsable(
    RouteConnectorLeg connector,
    RouteChainTarget target,
    RevvRoute nextRoute,
  ) {
    final maxAbsolute = math.max(7.0, target.targetDistanceKm * 0.34);
    if (connector.distanceKm > maxAbsolute) return false;
    if (connector.distanceKm > math.max(2.5, nextRoute.distanceKm * 1.9)) {
      return false;
    }
    return true;
  }

  double _targetFit(double totalKm, double targetKm) {
    final tolerance = math.max(8.0, targetKm * 0.45);
    return (1 - ((totalKm - targetKm).abs() / tolerance))
        .clamp(0.0, 1.0)
        .toDouble();
  }

  bool _isTargetAcceptable(RouteChain chain) {
    final tolerance = math.max(8.0, chain.target.targetDistanceKm * 0.28);
    return chain.targetDeltaKm <= tolerance;
  }

  Future<RouteChain?> _hydrateConnectors(
    RouteChain chain, {
    required RouteConnectorResolver resolveConnector,
    required LatLng? origin,
  }) async {
    if (chain.routeLegs.length < 2) return null;
    final connectors = <RouteConnectorLeg>[];
    for (var i = 1; i < chain.routeLegs.length; i++) {
      final connector = await resolveConnector(
        chain.routeLegs[i - 1],
        chain.routeLegs[i],
      );
      if (connector == null || !connector.hasRoadGeometry) return null;
      connectors.add(connector);
    }
    final hydrated = RouteChain(
      target: chain.target,
      routeLegs: chain.routeLegs,
      connectors: connectors,
    );
    return hydrated.copyWith(score: scoreChain(hydrated, origin: origin));
  }

  double _connectorPenalty(RouteChain chain) {
    final ratioPenalty = chain.connectorRatio * 40;
    final absolutePenalty = chain.connectors.fold(
      0.0,
      (total, leg) => total + math.max(0.0, leg.distanceKm - 4.0) * 0.9,
    );
    return ratioPenalty + absolutePenalty;
  }

  double _backtrackingPenalty(RouteChain chain, LatLng? origin) {
    final points = <LatLng>[
      ?origin,
      for (final leg in chain.routeLegs) ...[leg.start, leg.end],
    ];
    var penalty = 0.0;
    for (var i = 2; i < points.length; i++) {
      final angle = _turnAngle(points[i - 2], points[i - 1], points[i]).abs();
      if (angle > 135) {
        penalty += 6.0;
      } else if (angle > 110) {
        penalty += 3.0;
      }
    }
    return penalty;
  }

  double _similarityPenalty(List<RouteChainRouteLeg> legs) {
    var penalty = 0.0;
    for (var i = 0; i < legs.length; i++) {
      for (var j = i + 1; j < legs.length; j++) {
        final left = legs[i].route;
        final right = legs[j].route;
        final centerKm = RevvRoute.haversineKm(
          left.centerPoint,
          right.centerPoint,
        );
        if (centerKm < 1.5) {
          penalty += 10.0;
        } else if (centerKm < 3.5) {
          penalty += 5.0;
        }
        if (_approximateNodeOverlap(left.nodes, right.nodes) > 0.35) {
          penalty += 8.0;
        }
      }
    }
    return penalty;
  }

  double _approximateNodeOverlap(List<LatLng> left, List<LatLng> right) {
    if (left.isEmpty || right.isEmpty) return 0;
    final sampleStep = math.max(1, left.length ~/ 12);
    var sampled = 0;
    var close = 0;
    for (var i = 0; i < left.length; i += sampleStep) {
      sampled++;
      if (_nearestNodeKm(left[i], right) <= 0.18) close++;
    }
    return sampled == 0 ? 0 : close / sampled;
  }

  double _nearestNodeKm(LatLng point, List<LatLng> nodes) {
    var best = double.infinity;
    for (final node in nodes) {
      best = math.min(best, RevvRoute.haversineKm(point, node));
    }
    return best;
  }

  double _turnAngle(LatLng a, LatLng b, LatLng c) {
    final ab = _vector(a, b);
    final bc = _vector(b, c);
    final abLen = math.sqrt(ab.$1 * ab.$1 + ab.$2 * ab.$2);
    final bcLen = math.sqrt(bc.$1 * bc.$1 + bc.$2 * bc.$2);
    if (abLen <= 0 || bcLen <= 0) return 0;
    final dot = ab.$1 * bc.$1 + ab.$2 * bc.$2;
    final cosine = (dot / (abLen * bcLen)).clamp(-1.0, 1.0).toDouble();
    return math.acos(cosine) * 180 / math.pi;
  }

  (double, double) _vector(LatLng from, LatLng to) {
    final latRad = from.lat * math.pi / 180;
    return (
      (to.lng - from.lng) * math.cos(latRad) * 111.32,
      (to.lat - from.lat) * 110.54,
    );
  }
}

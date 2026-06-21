import 'dart:math' as math;

import 'revv_route.dart';

enum RouteChainTarget {
  minutes30(30),
  minutes60(60),
  minutes90(90);

  final int minutes;

  const RouteChainTarget(this.minutes);

  double get targetDistanceKm => minutes.toDouble();

  String get label => '$minutes분';
}

class RouteChainRouteLeg {
  final RevvRoute route;
  final bool reversed;

  const RouteChainRouteLeg({required this.route, this.reversed = false});

  List<LatLng> get nodes {
    final source = route.nodes;
    return reversed ? source.reversed.toList(growable: false) : source;
  }

  LatLng get start => nodes.first;

  LatLng get end => nodes.last;
}

class RouteConnectorLeg {
  final String fromRouteId;
  final String toRouteId;
  final LatLng from;
  final LatLng to;
  final double distanceKm;
  final List<LatLng> polyline;

  const RouteConnectorLeg({
    required this.fromRouteId,
    required this.toRouteId,
    required this.from,
    required this.to,
    required this.distanceKm,
    this.polyline = const [],
  });

  factory RouteConnectorLeg.between(
    RouteChainRouteLeg fromLeg,
    RouteChainRouteLeg toLeg, {
    List<LatLng> polyline = const [],
    double? distanceKm,
  }) {
    final from = fromLeg.end;
    final to = toLeg.start;
    return RouteConnectorLeg(
      fromRouteId: fromLeg.route.id,
      toRouteId: toLeg.route.id,
      from: from,
      to: to,
      distanceKm: distanceKm ?? RevvRoute.haversineKm(from, to),
      polyline: polyline,
    );
  }

  bool get hasRoadGeometry => _normalizedPolyline().length >= 2;

  List<LatLng> get nodes {
    final normalized = _normalizedPolyline();
    return normalized.length >= 2 ? normalized : [from, to];
  }

  List<LatLng> _normalizedPolyline() {
    if (polyline.length < 2) return const [];
    final result = <LatLng>[];
    if (!_sameLatLng(polyline.first, from)) result.add(from);
    result.addAll(polyline);
    if (!_sameLatLng(result.last, to)) result.add(to);
    return result;
  }
}

class RouteChain {
  final RouteChainTarget target;
  final List<RouteChainRouteLeg> routeLegs;
  final List<RouteConnectorLeg> connectors;
  final double score;

  const RouteChain({
    required this.target,
    required this.routeLegs,
    required this.connectors,
    this.score = 0,
  });

  double get routeDistanceKm => routeLegs.fold(
    0.0,
    (total, leg) => total + math.max(0.0, leg.route.distanceKm),
  );

  double get connectorDistanceKm => connectors.fold(
    0.0,
    (total, leg) => total + math.max(0.0, leg.distanceKm),
  );

  double get totalDistanceKm => routeDistanceKm + connectorDistanceKm;

  double get connectorRatio {
    final total = totalDistanceKm;
    if (total <= 0) return 0;
    return connectorDistanceKm / total;
  }

  double get targetDeltaKm => (totalDistanceKm - target.targetDistanceKm).abs();

  bool get hasDrivableConnectors {
    if (connectors.length != math.max(0, routeLegs.length - 1)) return false;
    return connectors.every((connector) => connector.hasRoadGeometry);
  }

  List<LatLng> get mergedNodes => _merge().nodes;

  List<RouteSegmentRange> get segments => _merge().segments;

  RevvRoute toRevvRoute({LatLng? origin}) {
    final merge = _merge();
    final nodes = merge.nodes;
    final distanceKm = totalDistanceKm;
    final weightedWinding = _weightedWindingScore();
    final connectorAdjustedScore = (weightedWinding - connectorRatio * 2.0)
        .clamp(1.0, 10.0)
        .toDouble();
    final sharpCurveCount = routeLegs.fold(
      0,
      (total, leg) => total + leg.route.sharpCurveCount,
    );
    final stopSignCount = routeLegs.fold(
      0,
      (total, leg) => total + leg.route.stopSignCount,
    );
    final trafficSignalCount = routeLegs.fold(
      0,
      (total, leg) => total + leg.route.trafficSignalCount,
    );
    final weightedStops = stopSignCount + trafficSignalCount * 1.5;
    final stopControlDensity = distanceKm <= 0
        ? 0.0
        : weightedStops / distanceKm;
    return RevvRoute(
      id: _compositeId(),
      name: 'Smart Chain ${target.label}',
      nodes: nodes,
      distanceKm: distanceKm,
      windingScore: connectorAdjustedScore,
      starRating: RevvRoute.toStarRating(connectorAdjustedScore),
      sharpCurveCount: sharpCurveCount,
      elevationDelta: routeLegs.fold(
        0.0,
        (total, leg) => total + leg.route.elevationDelta,
      ),
      centerPoint: _centerOf(nodes),
      distanceFromUser: origin == null || nodes.isEmpty
          ? (routeLegs.isEmpty ? 0 : routeLegs.first.route.distanceFromUser)
          : RevvRoute.haversineKm(origin, nodes.first),
      tightCurveKm: routeLegs.fold(
        0.0,
        (total, leg) => total + leg.route.tightCurveKm,
      ),
      mediumCurveKm: routeLegs.fold(
        0.0,
        (total, leg) => total + leg.route.mediumCurveKm,
      ),
      maxContinuousKm: routeLegs.fold(
        0.0,
        (best, leg) => math.max(best, leg.route.maxContinuousKm),
      ),
      isLoop:
          nodes.length > 1 &&
          RevvRoute.haversineKm(nodes.first, nodes.last) <= 3,
      routeRankScore: score,
      funScore: _weightedMetric(
        (route) => route.funScore > 0 ? route.funScore : route.windingScore,
      ),
      flowScore: _weightedMetric(_routeFlowScore),
      driveabilityPenalty: _compositeDriveability(),
      stopSignCount: stopSignCount,
      trafficSignalCount: trafficSignalCount,
      stopControlDensity: stopControlDensity,
      roadClassBucket: 'smart_chain',
      isNamed: routeLegs.every((leg) => leg.route.isNamed),
      isFacilityLike: routeLegs.any((leg) => leg.route.isFacilityLike),
      isBridgeLike: routeLegs.any((leg) => leg.route.isBridgeLike),
      isConnectorLike: routeLegs.any((leg) => leg.route.isConnectorLike),
      isMajorRoadLike: routeLegs.any((leg) => leg.route.isMajorRoadLike),
      isPrivateLike: routeLegs.any((leg) => leg.route.isPrivateLike),
      qualityLabel: 'smart-chain',
      routeCharacter: 'SMART_CHAIN',
      primaryReason: '${routeLegs.length}개 와인딩 구간을 ${target.label} 목표에 맞춰 연결',
      cautionNote: hasDrivableConnectors
          ? '회색 연결 구간은 와인딩을 이어주는 일반 주행 구간입니다.'
          : '회색 연결 구간은 실제 길찾기 API 전 거리 기반 placeholder입니다.',
      roadNames: _uniqueStrings(routeLegs.expand((leg) => leg.route.roadNames)),
      surfaceSummary: _firstNonEmpty(
        routeLegs.map((leg) => leg.route.surfaceSummary),
      ),
      speedLimitSummary: _firstNonEmpty(
        routeLegs.map((leg) => leg.route.speedLimitSummary),
      ),
      nearbyPoiNames: _uniqueStrings(
        routeLegs.expand((leg) => leg.route.nearbyPoiNames),
      ),
      chainSegments: merge.segments,
    );
  }

  RouteChain copyWith({double? score}) {
    return RouteChain(
      target: target,
      routeLegs: routeLegs,
      connectors: connectors,
      score: score ?? this.score,
    );
  }

  double _weightedWindingScore() {
    final routeKm = routeDistanceKm;
    if (routeKm <= 0) return 0;
    final weighted = routeLegs.fold(
      0.0,
      (total, leg) =>
          total + leg.route.windingScore * math.max(0.0, leg.route.distanceKm),
    );
    return weighted / routeKm;
  }

  double _weightedMetric(double Function(RevvRoute route) valueOf) {
    final routeKm = routeDistanceKm;
    if (routeKm <= 0) return 0;
    final weighted = routeLegs.fold(
      0.0,
      (total, leg) =>
          total + valueOf(leg.route) * math.max(0.0, leg.route.distanceKm),
    );
    return weighted / routeKm;
  }

  double _routeFlowScore(RevvRoute route) {
    if (route.flowScore > 0) return route.flowScore.clamp(0.15, 1.0).toDouble();
    final weightedStops = route.stopSignCount + route.trafficSignalCount * 1.5;
    final density = route.stopControlDensity > 0
        ? route.stopControlDensity
        : weightedStops / math.max(route.distanceKm, 1.0);
    final continuityBoost = route.maxContinuousKm >= 1.5 ? 0.08 : 0.0;
    return (1.0 - density * 0.35 + continuityBoost).clamp(0.15, 1.0).toDouble();
  }

  double _compositeDriveability() {
    final base = _weightedMetric(_routeDriveability);
    final connectorMultiplier = (1.0 - connectorRatio * 0.35).clamp(0.05, 1.0);
    return (base * connectorMultiplier).clamp(0.05, 1.0).toDouble();
  }

  double _routeDriveability(RevvRoute route) {
    if (route.driveabilityPenalty > 0) {
      return route.driveabilityPenalty.clamp(0.05, 1.0).toDouble();
    }
    var multiplier = 1.0;
    if (!route.isNamed) multiplier *= 0.78;
    if (route.isFacilityLike) multiplier *= 0.08;
    if (route.isConnectorLike) multiplier *= 0.18;
    if (route.isBridgeLike) multiplier *= 0.28;
    if (route.isMajorRoadLike) multiplier *= 0.55;
    if (route.isPrivateLike) multiplier *= 0.18;
    return multiplier.clamp(0.05, 1.0).toDouble();
  }

  _RouteChainMerge _merge() {
    final nodes = <LatLng>[];
    final segments = <RouteSegmentRange>[];

    for (var i = 0; i < routeLegs.length; i++) {
      final leg = routeLegs[i];
      final legNodes = leg.nodes;
      if (legNodes.length < 2) continue;

      if (i > 0 && i - 1 < connectors.length && nodes.isNotEmpty) {
        final connector = connectors[i - 1];
        final startIndex = nodes.length - 1;
        final connectorNodes = connector.nodes;
        for (final node in connectorNodes) {
          if (nodes.isNotEmpty && _samePoint(nodes.last, node)) continue;
          nodes.add(node);
        }
        if (nodes.length - 1 > startIndex) {
          segments.add(
            RouteSegmentRange(
              kind: RouteSegmentKind.connector,
              startNodeIndex: startIndex,
              endNodeIndex: nodes.length - 1,
              distanceKm: connector.distanceKm,
              label: 'Connector',
            ),
          );
        }
      }

      final startIndex = nodes.isEmpty ? 0 : nodes.length - 1;
      if (nodes.isEmpty) {
        nodes.addAll(legNodes);
      } else if (_samePoint(nodes.last, legNodes.first)) {
        nodes.addAll(legNodes.skip(1));
      } else {
        nodes.addAll(legNodes);
      }
      if (nodes.length - 1 > startIndex) {
        segments.add(
          RouteSegmentRange(
            kind: RouteSegmentKind.winding,
            startNodeIndex: startIndex,
            endNodeIndex: nodes.length - 1,
            distanceKm: leg.route.distanceKm,
            label: leg.route.name,
            sourceRouteId: leg.route.id,
          ),
        );
      }
    }

    return _RouteChainMerge(nodes: nodes, segments: segments);
  }

  String _compositeId() {
    final ids = routeLegs.map((leg) => leg.route.id.replaceAll(':', '_'));
    return 'chain:${target.minutes}:${ids.join("+")}';
  }

  static bool _samePoint(LatLng a, LatLng b) {
    return _sameLatLng(a, b);
  }

  static LatLng _centerOf(List<LatLng> nodes) {
    if (nodes.isEmpty) return const LatLng(0, 0);
    final lat =
        nodes.fold(0.0, (total, node) => total + node.lat) / nodes.length;
    final lng =
        nodes.fold(0.0, (total, node) => total + node.lng) / nodes.length;
    return LatLng(lat, lng);
  }

  static List<String> _uniqueStrings(Iterable<String> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isEmpty || !seen.add(trimmed)) continue;
      result.add(trimmed);
    }
    return result;
  }

  static String _firstNonEmpty(Iterable<String> values) {
    for (final value in values) {
      if (value.trim().isNotEmpty) return value;
    }
    return '';
  }
}

bool _sameLatLng(LatLng a, LatLng b) {
  return (a.lat - b.lat).abs() < 0.000001 && (a.lng - b.lng).abs() < 0.000001;
}

class _RouteChainMerge {
  final List<LatLng> nodes;
  final List<RouteSegmentRange> segments;

  const _RouteChainMerge({required this.nodes, required this.segments});
}

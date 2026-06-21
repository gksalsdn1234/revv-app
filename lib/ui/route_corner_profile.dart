import 'dart:math' as math;

import '../models/revv_route.dart';

enum RouteCornerType {
  kink,
  sweeper,
  medium,
  tight,
  hairpin,
  switchback,
  chicane,
}

class RouteCornerProfile {
  final List<RouteCorner> corners;
  final List<double> cumulativeM;
  final double totalM;

  const RouteCornerProfile({
    required this.corners,
    required this.cumulativeM,
    required this.totalM,
  });

  factory RouteCornerProfile.fromNodes(List<LatLng> nodes) {
    if (nodes.length < 3) {
      return const RouteCornerProfile(corners: [], cumulativeM: [], totalM: 0);
    }

    final cumulativeM = _cumulativeMeters(nodes);
    final raw = <RouteCorner>[];
    for (var i = 1; i < nodes.length - 1; i++) {
      final turn = _turnDegrees(nodes[i - 1], nodes[i], nodes[i + 1]);
      final absTurn = turn.abs();
      if (absTurn < 20) continue;
      raw.add(
        RouteCorner(
          nodeIndex: i,
          apex: nodes[i],
          alongM: cumulativeM[i],
          turnDegrees: turn,
          severity: _cornerSeverity(absTurn),
          type: _baseCornerType(absTurn, cumulativeM, i),
          nextGapM: null,
          sequenceCount: 1,
        ),
      );
    }

    final corners = <RouteCorner>[];
    for (var i = 0; i < raw.length; i++) {
      final nextGap = i + 1 < raw.length
          ? raw[i + 1].alongM - raw[i].alongM
          : null;
      final sequenceCount = _sequenceCount(raw, i);
      corners.add(
        raw[i].copyWith(
          nextGapM: nextGap,
          sequenceCount: sequenceCount,
          type: _sequenceType(raw, i, sequenceCount),
        ),
      );
    }

    return RouteCornerProfile(
      corners: List.unmodifiable(corners),
      cumulativeM: List.unmodifiable(cumulativeM),
      totalM: cumulativeM.last,
    );
  }
}

class RouteCorner {
  final int nodeIndex;
  final LatLng apex;
  final double alongM;
  final double turnDegrees;
  final int severity;
  final RouteCornerType type;
  final double? nextGapM;
  final int sequenceCount;

  const RouteCorner({
    required this.nodeIndex,
    required this.apex,
    required this.alongM,
    required this.turnDegrees,
    required this.severity,
    required this.type,
    required this.nextGapM,
    required this.sequenceCount,
  });

  RouteCorner copyWith({
    RouteCornerType? type,
    double? nextGapM,
    int? sequenceCount,
  }) {
    return RouteCorner(
      nodeIndex: nodeIndex,
      apex: apex,
      alongM: alongM,
      turnDegrees: turnDegrees,
      severity: severity,
      type: type ?? this.type,
      nextGapM: nextGapM ?? this.nextGapM,
      sequenceCount: sequenceCount ?? this.sequenceCount,
    );
  }
}

List<double> _cumulativeMeters(List<LatLng> nodes) {
  final cumulative = List<double>.filled(nodes.length, 0);
  var totalM = 0.0;
  for (var i = 1; i < nodes.length; i++) {
    totalM += RevvRoute.haversineKm(nodes[i - 1], nodes[i]) * 1000;
    cumulative[i] = totalM;
  }
  return cumulative;
}

int _sequenceCount(List<RouteCorner> raw, int start) {
  var count = 1;
  for (var i = start + 1; i < raw.length; i++) {
    final gapM = raw[i].alongM - raw[i - 1].alongM;
    if (gapM > 180) break;
    count++;
  }
  return count;
}

RouteCornerType _sequenceType(
  List<RouteCorner> raw,
  int index,
  int sequenceCount,
) {
  final base = raw[index].type;
  if (base == RouteCornerType.hairpin && sequenceCount >= 2) {
    return RouteCornerType.switchback;
  }
  if (sequenceCount >= 3 && _alternates(raw, index, sequenceCount)) {
    return RouteCornerType.chicane;
  }
  return base;
}

bool _alternates(List<RouteCorner> raw, int index, int count) {
  final limit = math.min(raw.length - 1, index + count - 1);
  for (var i = index + 1; i <= limit; i++) {
    if (raw[i - 1].turnDegrees.sign == raw[i].turnDegrees.sign) return false;
  }
  return true;
}

RouteCornerType _baseCornerType(
  double absTurn,
  List<double> cumulativeM,
  int nodeIndex,
) {
  if (absTurn >= 100) return RouteCornerType.hairpin;
  if (absTurn >= 68) return RouteCornerType.tight;
  if (absTurn >= 42) return RouteCornerType.medium;

  final nextSegmentM = nodeIndex + 1 < cumulativeM.length
      ? cumulativeM[nodeIndex + 1] - cumulativeM[nodeIndex]
      : 0.0;
  if (nextSegmentM >= 180) return RouteCornerType.sweeper;
  return RouteCornerType.kink;
}

int _cornerSeverity(double absTurn) {
  if (absTurn >= 68) return 3;
  if (absTurn >= 42) return 2;
  if (absTurn >= 26) return 1;
  return 0;
}

double _turnDegrees(LatLng a, LatLng b, LatLng c) {
  final inBearing = _bearingDegrees(a, b);
  final outBearing = _bearingDegrees(b, c);
  var delta = outBearing - inBearing;
  while (delta > 180) {
    delta -= 360;
  }
  while (delta < -180) {
    delta += 360;
  }
  return delta;
}

double _bearingDegrees(LatLng from, LatLng to) {
  final lat1 = from.lat * math.pi / 180;
  final lat2 = to.lat * math.pi / 180;
  final dLng = (to.lng - from.lng) * math.pi / 180;
  final y = math.sin(dLng) * math.cos(lat2);
  final x =
      math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

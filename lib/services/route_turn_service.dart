import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../core/app_language.dart';
import '../models/revv_route.dart';
import 'bounded_http_response.dart';
import 'mapbox_service.dart';

class NavStep {
  static const minBriefingStraightM = 1000.0;

  final int sequence;
  final String maneuverType;
  final String? modifier;
  final LatLng location;
  final double distanceFromStartM;
  final double segmentDistanceM;

  const NavStep({
    required this.sequence,
    required this.maneuverType,
    required this.modifier,
    required this.location,
    required this.distanceFromStartM,
    required this.segmentDistanceM,
  });

  bool get isStraightAhead {
    final normalizedModifier = modifier?.trim().toLowerCase();
    if (normalizedModifier?.contains('left') == true ||
        normalizedModifier?.contains('right') == true) {
      return false;
    }
    if (normalizedModifier == 'straight') return true;
    return switch (maneuverType.trim().toLowerCase()) {
      'depart' ||
      'continue' ||
      'new name' ||
      'notification' ||
      'use lane' ||
      '' => true,
      _ => false,
    };
  }

  bool get isBriefingWorthy =>
      !isStraightAhead || segmentDistanceM >= minBriefingStraightM;

  String call(AppLanguage language) {
    final type = maneuverType.trim().toLowerCase();
    final normalizedModifier = modifier?.trim().toLowerCase() ?? '';
    final right = normalizedModifier.contains('right');
    final left = normalizedModifier.contains('left');
    final uTurn = normalizedModifier.contains('uturn');
    final direction = right
        ? _t(language, ko: '우측', en: 'right', fr: 'droite')
        : left
        ? _t(language, ko: '좌측', en: 'left', fr: 'gauche')
        : _t(language, ko: '직진', en: 'straight', fr: 'tout droit');
    final frenchDirection = right
        ? 'à droite'
        : left
        ? 'à gauche'
        : 'tout droit';
    if (isStraightAhead) return direction;
    if (uTurn) {
      return _t(language, ko: '유턴', en: 'U-turn', fr: 'demi-tour');
    }
    return switch (type) {
      'fork' => _t(
        language,
        ko: '$direction 유지',
        en: 'keep $direction',
        fr: 'restez $frenchDirection',
      ),
      'off ramp' => _t(
        language,
        ko: '$direction 진출',
        en: 'exit $direction',
        fr: 'sortie $frenchDirection',
      ),
      'on ramp' => _t(
        language,
        ko: '$direction 진입',
        en: 'ramp $direction',
        fr: 'bretelle $frenchDirection',
      ),
      'merge' => _t(
        language,
        ko: '$direction 합류',
        en: 'merge $direction',
        fr: 'fusion $frenchDirection',
      ),
      'roundabout' || 'rotary' || 'roundabout turn' => _t(
        language,
        ko: '회전교차로',
        en: 'roundabout',
        fr: 'rond-point',
      ),
      'exit roundabout' || 'exit rotary' => _t(
        language,
        ko: '회전교차로 진출',
        en: 'exit roundabout',
        fr: 'sortie du rond-point',
      ),
      'end of road' => _t(
        language,
        ko: '끝에서 $direction',
        en: '$direction at the end',
        fr: '$frenchDirection au bout',
      ),
      'arrive' => _t(language, ko: '피니시', en: 'finish', fr: 'arrivée'),
      _ => _t(
        language,
        ko: right || left ? direction : '직진',
        en: right || left ? direction : 'straight',
        fr: right || left ? frenchDirection : 'tout droit',
      ),
    };
  }
}

class NavStepProgress {
  final NavStep step;
  final double aheadM;

  const NavStepProgress({required this.step, required this.aheadM});
}

class RouteTurnService {
  RouteTurnService({
    http.Client? client,
    String? accessToken,
    DateTime Function()? clock,
  }) : _client = client ?? http.Client(),
       _accessToken = accessToken ?? MapboxService.accessToken,
       _clock = clock ?? DateTime.now;

  static const recalculateCooldown = Duration(seconds: 60);
  static const _maxResponseBytes = 2 * 1024 * 1024;
  static const _maxSteps = 500;

  final http.Client _client;
  final String _accessToken;
  final DateTime Function() _clock;
  DateTime? _lastRecalculatedAt;

  void resetRecalculationCooldown() {
    _lastRecalculatedAt = null;
  }

  Future<List<NavStep>> fetchSteps(List<LatLng> routeNodes) async {
    if (_accessToken.isEmpty || routeNodes.length < 2) return const [];
    return _fetch(_downsampleWaypoints(routeNodes));
  }

  Future<List<NavStep>> fetchStepsForLegs(List<List<LatLng>> routeLegs) async {
    final legs = routeLegs
        .where((nodes) => nodes.length >= 2)
        .toList(growable: false);
    if (legs.isEmpty) return const [];
    final stepsByLeg = await Future.wait(legs.map(fetchSteps));
    final merged = <NavStep>[];
    NavStep? finalArrival;
    var distanceOffsetM = 0.0;
    for (var legIndex = 0; legIndex < legs.length; legIndex++) {
      final isLastLeg = legIndex == legs.length - 1;
      final cumulativeM = _cumulativeMeters(legs[legIndex]);
      for (final step in stepsByLeg[legIndex]) {
        if (legIndex > 0 && step.maneuverType == 'depart') continue;
        if (!isLastLeg && step.maneuverType == 'arrive') continue;
        final adjusted = NavStep(
          sequence: merged.length + 1,
          maneuverType: step.maneuverType,
          modifier: step.modifier,
          location: step.location,
          distanceFromStartM:
              distanceOffsetM +
              _nearestAlongM(step.location, legs[legIndex], cumulativeM),
          segmentDistanceM: step.segmentDistanceM,
        );
        if (step.maneuverType == 'arrive') {
          finalArrival = adjusted;
          continue;
        }
        if (merged.length < _maxSteps - 1) merged.add(adjusted);
      }
      distanceOffsetM += _polylineDistanceM(legs[legIndex]);
    }
    if (finalArrival != null) {
      merged.add(
        NavStep(
          sequence: merged.length + 1,
          maneuverType: finalArrival.maneuverType,
          modifier: finalArrival.modifier,
          location: finalArrival.location,
          distanceFromStartM: finalArrival.distanceFromStartM,
          segmentDistanceM: finalArrival.segmentDistanceM,
        ),
      );
    }
    return List.unmodifiable(merged);
  }

  Future<List<NavStep>> recalculateSteps({
    required LatLng current,
    required LatLng rejoin,
  }) async {
    final last = _lastRecalculatedAt;
    final now = _clock();
    if (last != null && now.difference(last) < recalculateCooldown) {
      return const [];
    }
    _lastRecalculatedAt = now;
    if (_accessToken.isEmpty) return const [];
    return _fetch([current, rejoin]);
  }

  Future<List<NavStep>> _fetch(List<LatLng> waypoints) async {
    try {
      final raw = await getBoundedResponseBody(
        _client,
        _directionsUri(waypoints),
        maxBytes: _maxResponseBytes,
      ).timeout(const Duration(seconds: 8));
      final body = jsonDecode(raw);
      if (body is! Map<String, dynamic>) return const [];
      return _parseSteps(body);
    } catch (_) {
      return const [];
    }
  }

  Uri _directionsUri(List<LatLng> waypoints) {
    final coordinates = waypoints
        .map((point) => '${point.lng},${point.lat}')
        .join(';');
    return Uri.https(
      'api.mapbox.com',
      '/directions/v5/mapbox/driving/$coordinates',
      {
        'access_token': _accessToken,
        'steps': 'true',
        'overview': 'false',
        'geometries': 'geojson',
        'alternatives': 'false',
        'language': 'en',
      },
    );
  }
}

double _polylineDistanceM(List<LatLng> nodes) {
  var distanceM = 0.0;
  for (var index = 1; index < nodes.length; index++) {
    distanceM += RevvRoute.haversineKm(nodes[index - 1], nodes[index]) * 1000;
  }
  return distanceM;
}

List<LatLng> _downsampleWaypoints(List<LatLng> nodes) {
  if (nodes.length <= 25) return List.unmodifiable(nodes);
  return List.unmodifiable(
    List.generate(25, (index) {
      final sourceIndex = (index * (nodes.length - 1) / 24).round();
      return nodes[sourceIndex];
    }),
  );
}

List<NavStep> _parseSteps(Map<String, dynamic> body) {
  final routes = body['routes'];
  if (routes is! List || routes.isEmpty) return const [];
  final route = routes.first;
  if (route is! Map<String, dynamic>) return const [];
  final legs = route['legs'];
  if (legs is! List) return const [];

  final steps = <NavStep>[];
  NavStep? finalArrival;
  NavStep? deferredNonArrival;
  var distanceFromStartM = 0.0;
  for (var legIndex = 0; legIndex < legs.length; legIndex++) {
    final leg = legs[legIndex];
    if (leg is! Map<String, dynamic>) continue;
    final rawSteps = leg['steps'];
    if (rawSteps is! List) continue;
    for (final rawStep in rawSteps) {
      if (rawStep is! Map<String, dynamic>) continue;
      final maneuver = rawStep['maneuver'];
      if (maneuver is! Map<String, dynamic>) continue;
      final location = _locationFrom(maneuver['location']);
      if (location == null) continue;
      final segmentDistanceM = _doubleFrom(rawStep['distance']);
      final maneuverType = maneuver['type']?.toString() ?? '';
      if (maneuverType == 'depart' && legIndex > 0) {
        distanceFromStartM += segmentDistanceM;
        continue;
      }
      if (maneuverType == 'arrive' && legIndex < legs.length - 1) {
        distanceFromStartM += segmentDistanceM;
        continue;
      }
      final step = NavStep(
        sequence: steps.length + 1,
        maneuverType: maneuverType,
        modifier: maneuver['modifier']?.toString(),
        location: location,
        distanceFromStartM: distanceFromStartM,
        segmentDistanceM: segmentDistanceM,
      );
      if (maneuverType == 'arrive') {
        finalArrival = step;
      } else if (steps.length < RouteTurnService._maxSteps - 1) {
        steps.add(step);
      } else {
        deferredNonArrival ??= step;
      }
      distanceFromStartM += segmentDistanceM;
    }
  }
  final tail = finalArrival ?? deferredNonArrival;
  if (tail != null && steps.length < RouteTurnService._maxSteps) {
    steps.add(
      NavStep(
        sequence: steps.length + 1,
        maneuverType: tail.maneuverType,
        modifier: tail.modifier,
        location: tail.location,
        distanceFromStartM: tail.distanceFromStartM,
        segmentDistanceM: tail.segmentDistanceM,
      ),
    );
  }
  return List.unmodifiable(steps);
}

NavStepProgress? nextStepProgress(
  LatLng position,
  List<LatLng> routeNodes,
  List<NavStep> steps, {
  double? routeProgress,
}) {
  if (routeNodes.length < 2 || steps.isEmpty) return null;
  final cumulativeM = _cumulativeMeters(routeNodes);
  final alongM = routeProgress == null
      ? _nearestAlongM(position, routeNodes, cumulativeM)
      : cumulativeM.last * routeProgress.clamp(0.0, 1.0);
  final remainingM = math.max(0.0, cumulativeM.last - alongM);
  for (final step in steps) {
    if (!step.isBriefingWorthy) continue;
    if (step.maneuverType == 'arrive') {
      if (remainingM > 800) continue;
      return NavStepProgress(step: step, aheadM: remainingM);
    }
    final aheadM = step.distanceFromStartM - alongM;
    if (aheadM >= -18) {
      return NavStepProgress(step: step, aheadM: math.max(0.0, aheadM));
    }
  }
  return null;
}

LatLng? nearestRoutePoint(
  LatLng position,
  List<LatLng> routeNodes, {
  double? routeProgress,
  double progressWindow = 0.08,
}) {
  if (routeNodes.length < 2) return null;
  final cumulativeM = _cumulativeMeters(routeNodes);
  final totalM = cumulativeM.last;
  final minAlongM = routeProgress == null
      ? 0.0
      : totalM * math.max(0.0, routeProgress - 0.01);
  final maxAlongM = routeProgress == null
      ? totalM
      : totalM * math.min(1.0, routeProgress + progressWindow);
  var bestDistanceM = double.infinity;
  LatLng? bestPoint;
  for (var i = 0; i < routeNodes.length - 1; i++) {
    final segmentStartM = cumulativeM[i];
    final segmentEndM = cumulativeM[i + 1];
    final segmentM = segmentEndM - segmentStartM;
    if (segmentM <= 0 || segmentEndM < minAlongM || segmentStartM > maxAlongM) {
      continue;
    }
    final projection = _projectOnSegment(
      position,
      routeNodes[i],
      routeNodes[i + 1],
      minT: ((minAlongM - segmentStartM) / segmentM).clamp(0.0, 1.0),
      maxT: ((maxAlongM - segmentStartM) / segmentM).clamp(0.0, 1.0),
    );
    if (projection.distanceM < bestDistanceM) {
      bestDistanceM = projection.distanceM;
      bestPoint = _interpolate(routeNodes[i], routeNodes[i + 1], projection.t);
    }
  }
  return bestPoint ?? routeNodes.last;
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

double _nearestAlongM(
  LatLng position,
  List<LatLng> nodes,
  List<double> cumulativeM,
) {
  var bestAlongM = 0.0;
  var bestDistanceM = double.infinity;
  for (var i = 0; i < nodes.length - 1; i++) {
    final segmentM = cumulativeM[i + 1] - cumulativeM[i];
    if (segmentM <= 0) continue;
    final projection = _projectOnSegment(position, nodes[i], nodes[i + 1]);
    if (projection.distanceM < bestDistanceM) {
      bestDistanceM = projection.distanceM;
      bestAlongM = cumulativeM[i] + segmentM * projection.t;
    }
  }
  return bestAlongM;
}

_SegmentProjection _projectOnSegment(
  LatLng p,
  LatLng a,
  LatLng b, {
  double minT = 0,
  double maxT = 1,
}) {
  final ap = _metersFrom(a, p);
  final ab = _metersFrom(a, b);
  final ab2 = ab.x * ab.x + ab.y * ab.y;
  final rawT = ab2 <= 0
      ? 0.0
      : ((ap.x * ab.x + ap.y * ab.y) / ab2).clamp(0.0, 1.0).toDouble();
  final t = rawT.clamp(minT, maxT).toDouble();
  final closestX = ab.x * t;
  final closestY = ab.y * t;
  final dx = ap.x - closestX;
  final dy = ap.y - closestY;
  return _SegmentProjection(t: t, distanceM: math.sqrt(dx * dx + dy * dy));
}

LatLng _interpolate(LatLng a, LatLng b, double t) {
  return LatLng(a.lat + (b.lat - a.lat) * t, a.lng + (b.lng - a.lng) * t);
}

_PointM _metersFrom(LatLng origin, LatLng point) {
  final latRad = origin.lat * math.pi / 180;
  return _PointM(
    x: (point.lng - origin.lng) * math.cos(latRad) * 111320,
    y: (point.lat - origin.lat) * 110540,
  );
}

LatLng? _locationFrom(Object? value) {
  if (value is! List || value.length < 2) return null;
  return LatLng(_doubleFrom(value[1]), _doubleFrom(value[0]));
}

double _doubleFrom(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

String _t(
  AppLanguage language, {
  required String ko,
  required String en,
  required String fr,
}) {
  return switch (language) {
    AppLanguage.korean => ko,
    AppLanguage.french => fr,
    _ => en,
  };
}

class _SegmentProjection {
  final double t;
  final double distanceM;

  const _SegmentProjection({required this.t, required this.distanceM});
}

class _PointM {
  final double x;
  final double y;

  const _PointM({required this.x, required this.y});
}

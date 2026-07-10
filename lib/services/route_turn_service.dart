import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../core/app_language.dart';
import '../models/revv_route.dart';
import 'mapbox_service.dart';

class NavStep {
  final int sequence;
  final String maneuverType;
  final String? modifier;
  final LatLng location;
  final double distanceFromStartM;

  const NavStep({
    required this.sequence,
    required this.maneuverType,
    required this.modifier,
    required this.location,
    required this.distanceFromStartM,
  });

  String call(AppLanguage language) {
    final right = modifier?.contains('right') == true;
    final left = modifier?.contains('left') == true;
    final direction = right
        ? _t(language, ko: '우측', en: 'right', fr: 'droite')
        : left
        ? _t(language, ko: '좌측', en: 'left', fr: 'gauche')
        : _t(language, ko: '직진', en: 'straight', fr: 'tout droit');
    return switch (maneuverType) {
      'fork' || 'off ramp' || 'on ramp' || 'merge' => _t(
        language,
        ko: '$direction 갈림길',
        en: 'fork $direction',
        fr: 'bifurcation $direction',
      ),
      'roundabout' || 'rotary' => _t(
        language,
        ko: '회전교차로',
        en: 'roundabout',
        fr: 'rond-point',
      ),
      'arrive' => _t(language, ko: '피니시', en: 'finish', fr: 'arrivée'),
      _ => _t(
        language,
        ko: '$direction 갈림길',
        en: right || left ? 'turn $direction' : direction,
        fr: right || left ? 'virage $direction' : direction,
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

  final http.Client _client;
  final String _accessToken;
  final DateTime Function() _clock;
  DateTime? _lastRecalculatedAt;

  Future<List<NavStep>> fetchSteps(List<LatLng> routeNodes) async {
    if (_accessToken.isEmpty || routeNodes.length < 2) return const [];
    return _fetch(_downsampleWaypoints(routeNodes));
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
      final response = await _client
          .get(_directionsUri(waypoints))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const [];
      }
      final body = jsonDecode(response.body);
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
  var distanceFromStartM = 0.0;
  for (final leg in legs) {
    if (leg is! Map<String, dynamic>) continue;
    final rawSteps = leg['steps'];
    if (rawSteps is! List) continue;
    for (final rawStep in rawSteps) {
      if (rawStep is! Map<String, dynamic>) continue;
      final maneuver = rawStep['maneuver'];
      if (maneuver is! Map<String, dynamic>) continue;
      final location = _locationFrom(maneuver['location']);
      if (location == null) continue;
      distanceFromStartM += _doubleFrom(rawStep['distance']);
      steps.add(
        NavStep(
          sequence: steps.length + 1,
          maneuverType: maneuver['type']?.toString() ?? '',
          modifier: maneuver['modifier']?.toString(),
          location: location,
          distanceFromStartM: distanceFromStartM,
        ),
      );
    }
  }
  return List.unmodifiable(steps);
}

NavStepProgress? nextStepProgress(
  LatLng position,
  List<LatLng> routeNodes,
  List<NavStep> steps,
) {
  if (routeNodes.length < 2 || steps.isEmpty) return null;
  final cumulativeM = _cumulativeMeters(routeNodes);
  final alongM = _nearestAlongM(position, routeNodes, cumulativeM);
  for (final step in steps) {
    final aheadM = step.distanceFromStartM - alongM;
    if (aheadM >= -18) {
      return NavStepProgress(step: step, aheadM: math.max(0.0, aheadM));
    }
  }
  return null;
}

LatLng? nearestRoutePoint(LatLng position, List<LatLng> routeNodes) {
  if (routeNodes.length < 2) return null;
  var bestDistanceM = double.infinity;
  LatLng? bestPoint;
  for (var i = 0; i < routeNodes.length - 1; i++) {
    final projection = _projectOnSegment(
      position,
      routeNodes[i],
      routeNodes[i + 1],
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

_SegmentProjection _projectOnSegment(LatLng p, LatLng a, LatLng b) {
  final ap = _metersFrom(a, p);
  final ab = _metersFrom(a, b);
  final ab2 = ab.x * ab.x + ab.y * ab.y;
  final t = ab2 <= 0
      ? 0.0
      : ((ap.x * ab.x + ap.y * ab.y) / ab2).clamp(0.0, 1.0).toDouble();
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

String _t(AppLanguage language, {
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

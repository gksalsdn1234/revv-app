import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../models/revv_route.dart';
import 'mapbox_service.dart';

class TransitLegEta {
  final List<LatLng> nodes;
  final double distanceKm;
  final int estimatedMinutes;

  const TransitLegEta({
    required this.nodes,
    required this.distanceKm,
    required this.estimatedMinutes,
  });
}

class TransitEtaService {
  static const _requestTimeout = Duration(seconds: 8);

  final http.Client _client;
  final Map<String, List<TransitLegEta>> _cache = {};

  TransitEtaService({http.Client? client}) : _client = client ?? http.Client();

  Future<List<TransitLegEta>> routeLegs(List<LatLng> waypoints) async {
    if (waypoints.length < 2) return const [];
    final key = _cacheKey(waypoints);
    final cached = _cache[key];
    if (cached != null) return cached;

    final legs = await _fetchMapboxLegs(waypoints) ?? fallbackLegs(waypoints);
    _cache[key] = legs;
    return legs;
  }

  Future<List<TransitLegEta>?> _fetchMapboxLegs(List<LatLng> waypoints) async {
    if (!MapboxService.isConfigured) return null;
    try {
      final response = await _client
          .get(_directionsUri(waypoints))
          .timeout(_requestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      return parseMapboxDirectionsLegs(decoded, waypoints);
    } catch (_) {
      return null;
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
        'alternatives': 'false',
        'geometries': 'geojson',
        'overview': 'full',
        'steps': 'true',
        'access_token': MapboxService.accessToken,
      },
    );
  }
}

List<TransitLegEta> fallbackLegs(List<LatLng> waypoints) {
  final legs = <TransitLegEta>[];
  for (var i = 0; i < waypoints.length - 1; i++) {
    final start = waypoints[i];
    final end = waypoints[i + 1];
    final directKm = RevvRoute.haversineKm(start, end);
    // 1.3 is a conservative rural-road detour factor: it covers non-grid road
    // curvature and access-road offsets while keeping fallback ETA predictable.
    final roadKm = directKm * 1.3;
    legs.add(
      TransitLegEta(
        nodes: [start, end],
        distanceKm: roadKm,
        estimatedMinutes: math.max(1, roadKm.round()),
      ),
    );
  }
  return legs;
}

List<TransitLegEta>? parseMapboxDirectionsLegs(
  Map<String, dynamic> json,
  List<LatLng> waypoints,
) {
  final routes = json['routes'];
  if (routes is! List || routes.isEmpty) return null;
  final route = routes.first;
  if (route is! Map<String, dynamic>) return null;
  final rawLegs = route['legs'];
  if (rawLegs is! List || rawLegs.length != waypoints.length - 1) return null;

  final parsed = <TransitLegEta>[];
  for (var i = 0; i < rawLegs.length; i++) {
    final leg = rawLegs[i];
    if (leg is! Map<String, dynamic>) return null;
    final distanceKm = ((leg['distance'] as num?)?.toDouble() ?? 0) / 1000;
    final durationSeconds = (leg['duration'] as num?)?.toDouble() ?? 0;
    parsed.add(
      TransitLegEta(
        nodes: _legNodes(leg, waypoints[i], waypoints[i + 1]),
        distanceKm: distanceKm,
        estimatedMinutes: math.max(1, (durationSeconds / 60).round()),
      ),
    );
  }
  return parsed;
}

List<LatLng> _legNodes(Map<String, dynamic> leg, LatLng start, LatLng end) {
  final nodes = <LatLng>[start];
  final steps = leg['steps'];
  if (steps is List) {
    for (final step in steps) {
      if (step is! Map<String, dynamic>) continue;
      final geometry = step['geometry'];
      if (geometry is! Map<String, dynamic>) continue;
      final coordinates = geometry['coordinates'];
      if (coordinates is! List) continue;
      for (final coordinate in coordinates) {
        if (coordinate is! List || coordinate.length < 2) continue;
        nodes.add(
          LatLng(
            (coordinate[1] as num).toDouble(),
            (coordinate[0] as num).toDouble(),
          ),
        );
      }
    }
  }
  nodes.add(end);
  return _dedupeAdjacent(nodes);
}

List<LatLng> _dedupeAdjacent(List<LatLng> nodes) {
  final deduped = <LatLng>[];
  for (final node in nodes) {
    if (deduped.isEmpty ||
        deduped.last.lat != node.lat ||
        deduped.last.lng != node.lng) {
      deduped.add(node);
    }
  }
  return deduped;
}

String _cacheKey(List<LatLng> waypoints) {
  return waypoints
      .map(
        (point) =>
            '${point.lat.toStringAsFixed(5)},${point.lng.toStringAsFixed(5)}',
      )
      .join('|');
}

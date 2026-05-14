import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/revv_route.dart';
import 'mapbox_service.dart';

class RouteGeometryMatcher {
  RouteGeometryMatcher._();

  static final RouteGeometryMatcher instance = RouteGeometryMatcher._();

  static const _cachePrefix = 'route_geometry_match_v1_';
  static const _maxMapboxMatchingPoints = 90;
  static const _requestTimeout = Duration(seconds: 8);

  Future<List<LatLng>> matchRoute(RevvRoute route) async {
    if (!MapboxService.isConfigured || route.nodes.length < 2) {
      return route.nodes;
    }

    final cached = await _readCached(route.id);
    if (cached.length >= 2) return cached;

    final sampled = downsampleForMatching(
      route.nodes,
      maxPoints: _maxMapboxMatchingPoints,
    );
    if (sampled.length < 2) return route.nodes;

    try {
      final uri = _matchingUri(sampled);
      final response = await http.get(uri).timeout(_requestTimeout);
      if (response.statusCode != 200) {
        if (kDebugMode) {
          debugPrint(
            '[RouteGeometryMatcher] map matching skipped: ${response.statusCode}',
          );
        }
        return route.nodes;
      }

      final matched = parseMatchedGeometry(response.body);
      if (!_isUsableMatch(route.nodes, matched)) return route.nodes;

      await _writeCached(route.id, matched);
      return matched;
    } on TimeoutException {
      if (kDebugMode) {
        debugPrint('[RouteGeometryMatcher] map matching timed out');
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[RouteGeometryMatcher] map matching failed: ${error.runtimeType}',
        );
      }
    }
    return route.nodes;
  }

  Uri _matchingUri(List<LatLng> sampled) {
    final coordinates = sampled
        .map((p) => '${_coord(p.lng)},${_coord(p.lat)}')
        .join(';');
    return Uri.https(
      'api.mapbox.com',
      '/matching/v5/mapbox/driving/$coordinates',
      {
        'access_token': MapboxService.accessToken,
        'geometries': 'geojson',
        'overview': 'full',
        'tidy': 'true',
      },
    );
  }

  static String _coord(double value) => value.toStringAsFixed(6);

  Future<List<LatLng>> _readCached(String routeId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_cachePrefix$routeId');
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((item) {
            final map = item as Map<String, dynamic>;
            return LatLng(
              (map['lat'] as num).toDouble(),
              (map['lng'] as num).toDouble(),
            );
          })
          .where(_isValidPoint)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _writeCached(String routeId, List<LatLng> nodes) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = nodes
          .map((p) => {'lat': p.lat, 'lng': p.lng})
          .toList(growable: false);
      await prefs.setString('$_cachePrefix$routeId', jsonEncode(payload));
    } catch (_) {
      // Cache failure should never block driving.
    }
  }

  static bool _isUsableMatch(List<LatLng> original, List<LatLng> matched) {
    if (matched.length < 2 || original.length < 2) return false;
    if (RevvRoute.haversineKm(original.first, matched.first) > 2.0) {
      return false;
    }
    if (RevvRoute.haversineKm(original.last, matched.last) > 2.0) {
      return false;
    }
    return matched.every(_isValidPoint);
  }

  static bool _isValidPoint(LatLng point) {
    return point.lat >= -90 &&
        point.lat <= 90 &&
        point.lng >= -180 &&
        point.lng <= 180;
  }

  @visibleForTesting
  static List<LatLng> downsampleForMatching(
    List<LatLng> nodes, {
    int maxPoints = _maxMapboxMatchingPoints,
  }) {
    if (nodes.length <= maxPoints) return List<LatLng>.from(nodes);
    if (maxPoints < 2) return const [];

    final result = <LatLng>[nodes.first];
    final interiorCount = maxPoints - 2;
    final span = nodes.length - 1;
    for (int i = 1; i <= interiorCount; i++) {
      final index = (i * span / (interiorCount + 1)).round();
      final point = nodes[index.clamp(1, nodes.length - 2)];
      if (!identical(result.last, point)) result.add(point);
    }
    if (!identical(result.last, nodes.last)) result.add(nodes.last);
    return result;
  }

  @visibleForTesting
  static List<LatLng> parseMatchedGeometry(String raw) {
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final matchings = decoded['matchings'] as List<dynamic>?;
    if (matchings == null || matchings.isEmpty) return const [];
    final first = matchings.first as Map<String, dynamic>;
    final geometry = first['geometry'] as Map<String, dynamic>?;
    final coordinates = geometry?['coordinates'] as List<dynamic>?;
    if (coordinates == null) return const [];
    return coordinates
        .map((coord) {
          final pair = coord as List<dynamic>;
          if (pair.length < 2) return null;
          return LatLng(
            (pair[1] as num).toDouble(),
            (pair[0] as num).toDouble(),
          );
        })
        .nonNulls
        .where(_isValidPoint)
        .toList(growable: false);
  }
}

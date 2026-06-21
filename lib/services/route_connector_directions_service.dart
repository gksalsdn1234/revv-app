import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/revv_route.dart';
import '../models/route_chain.dart';
import 'mapbox_service.dart';

class RouteConnectorGeometry {
  final List<LatLng> nodes;
  final double distanceKm;

  const RouteConnectorGeometry({required this.nodes, required this.distanceKm});
}

class RouteConnectorDirectionsService {
  RouteConnectorDirectionsService._();

  static final RouteConnectorDirectionsService instance =
      RouteConnectorDirectionsService._();

  static const _cachePrefix = 'route_connector_directions_v1_';
  static const _requestTimeout = Duration(seconds: 7);

  Future<RouteConnectorLeg?> resolveConnector(
    RouteChainRouteLeg fromLeg,
    RouteChainRouteLeg toLeg,
  ) async {
    final placeholder = RouteConnectorLeg.between(fromLeg, toLeg);
    if (!MapboxService.isConfigured) return null;

    final cacheKey = _cacheKey(placeholder.from, placeholder.to);
    final cached = await _readCached(cacheKey);
    if (cached != null) {
      return RouteConnectorLeg.between(
        fromLeg,
        toLeg,
        polyline: cached.nodes,
        distanceKm: cached.distanceKm,
      );
    }

    try {
      final response = await http
          .get(_directionsUri(placeholder.from, placeholder.to))
          .timeout(_requestTimeout);
      if (response.statusCode != 200) {
        if (kDebugMode) {
          debugPrint(
            '[RouteConnectorDirections] skipped: ${response.statusCode}',
          );
        }
        return null;
      }

      final geometry = parseDirectionsGeometry(response.body);
      if (!_isUsableGeometry(placeholder, geometry)) return null;
      await _writeCached(cacheKey, geometry);
      return RouteConnectorLeg.between(
        fromLeg,
        toLeg,
        polyline: geometry.nodes,
        distanceKm: geometry.distanceKm,
      );
    } on TimeoutException {
      if (kDebugMode) {
        debugPrint('[RouteConnectorDirections] timed out');
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[RouteConnectorDirections] failed: ${error.runtimeType}');
      }
    }
    return null;
  }

  Uri _directionsUri(LatLng from, LatLng to) {
    final coordinates =
        '${_coord(from.lng)},${_coord(from.lat)};${_coord(to.lng)},${_coord(to.lat)}';
    return Uri.https(
      'api.mapbox.com',
      '/directions/v5/mapbox/driving/$coordinates',
      {
        'access_token': MapboxService.accessToken,
        'geometries': 'geojson',
        'overview': 'full',
        'alternatives': 'false',
      },
    );
  }

  static String _coord(double value) => value.toStringAsFixed(6);

  String _cacheKey(LatLng from, LatLng to) {
    return [
      _coord(from.lat),
      _coord(from.lng),
      _coord(to.lat),
      _coord(to.lng),
    ].join('_');
  }

  Future<RouteConnectorGeometry?> _readCached(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_cachePrefix$key');
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final nodes = ((decoded['nodes'] as List?) ?? const [])
          .map((item) {
            final node = item as Map<String, dynamic>;
            return LatLng(
              (node['lat'] as num).toDouble(),
              (node['lng'] as num).toDouble(),
            );
          })
          .where(_isValidPoint)
          .toList(growable: false);
      final distanceKm = (decoded['distanceKm'] as num?)?.toDouble() ?? 0;
      if (nodes.length < 2 || distanceKm <= 0) return null;
      return RouteConnectorGeometry(nodes: nodes, distanceKm: distanceKm);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCached(String key, RouteConnectorGeometry geometry) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_cachePrefix$key',
        jsonEncode({
          'distanceKm': geometry.distanceKm,
          'nodes': geometry.nodes
              .map((node) => {'lat': node.lat, 'lng': node.lng})
              .toList(growable: false),
        }),
      );
    } catch (_) {
      // Cache failure should not hide an otherwise usable connector.
    }
  }

  static bool _isUsableGeometry(
    RouteConnectorLeg placeholder,
    RouteConnectorGeometry geometry,
  ) {
    if (geometry.nodes.length < 2 || geometry.distanceKm <= 0) return false;
    if (RevvRoute.haversineKm(placeholder.from, geometry.nodes.first) > 1.5) {
      return false;
    }
    if (RevvRoute.haversineKm(placeholder.to, geometry.nodes.last) > 1.5) {
      return false;
    }
    final straightKm = math.max(placeholder.distanceKm, 0.1);
    final maxReasonableKm = math.max(straightKm * 3.5, straightKm + 8.0);
    if (geometry.distanceKm > maxReasonableKm) return false;
    return geometry.nodes.every(_isValidPoint);
  }

  static bool _isValidPoint(LatLng point) {
    return point.lat >= -90 &&
        point.lat <= 90 &&
        point.lng >= -180 &&
        point.lng <= 180;
  }

  @visibleForTesting
  static RouteConnectorGeometry parseDirectionsGeometry(String raw) {
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final routes = decoded['routes'] as List<dynamic>?;
    if (routes == null || routes.isEmpty) {
      return const RouteConnectorGeometry(nodes: [], distanceKm: 0);
    }
    final route = routes.first as Map<String, dynamic>;
    final geometry = route['geometry'] as Map<String, dynamic>?;
    final coordinates = geometry?['coordinates'] as List<dynamic>?;
    if (coordinates == null) {
      return const RouteConnectorGeometry(nodes: [], distanceKm: 0);
    }
    final nodes = coordinates
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
    final distanceKm = ((route['distance'] as num?)?.toDouble() ?? 0) / 1000;
    return RouteConnectorGeometry(nodes: nodes, distanceKm: distanceKm);
  }
}

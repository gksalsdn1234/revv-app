import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/revv_route.dart';
import '../models/nav_step.dart';
import 'mapbox_service.dart';

typedef RouteWithSteps = ({List<LatLng> polyline, List<NavStep> steps});

class DirectionsService {
  static Future<List<LatLng>> getRoute(LatLng from, LatLng to) =>
      getMultiRoute([from, to]);

  /// polyline + 턴바이턴 steps 동시 반환
  static Future<RouteWithSteps> getRouteWithSteps(LatLng from, LatLng to) async {
    const empty = (polyline: <LatLng>[], steps: <NavStep>[]);
    final coords = '${from.lng},${from.lat};${to.lng},${to.lat}';
    final url = Uri.parse(
      'https://api.mapbox.com/directions/v5/mapbox/driving/$coords'
      '?geometries=geojson&overview=full&steps=true'
      '&access_token=${MapboxService.accessToken}',
    );
    try {
      final res = await http.get(url).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return empty;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final routes = data['routes'] as List?;
      if (routes == null || routes.isEmpty) return empty;

      final route = routes[0] as Map<String, dynamic>;
      final polyline = (route['geometry']['coordinates'] as List)
          .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
          .toList();

      final legs = route['legs'] as List?;
      final stepsList = legs != null && legs.isNotEmpty
          ? (legs[0]['steps'] as List? ?? [])
          : [];
      final steps = stepsList
          .map((s) => NavStep.fromJson(s as Map<String, dynamic>))
          .toList();

      debugPrint('[DirectionsService] steps: ${steps.length}');
      return (polyline: polyline, steps: steps);
    } catch (e) {
      debugPrint('[DirectionsService] getRouteWithSteps error: $e');
      return empty;
    }
  }

  /// Mapbox Directions API — 최대 25 경유지 지원
  static Future<List<LatLng>> getMultiRoute(List<LatLng> waypoints) async {
    if (waypoints.length < 2) return [];
    final coords = waypoints.map((p) => '${p.lng},${p.lat}').join(';');
    final url = Uri.parse(
      'https://api.mapbox.com/directions/v5/mapbox/driving/$coords'
      '?geometries=geojson&overview=full&access_token=${MapboxService.accessToken}',
    );
    try {
      debugPrint('[DirectionsService] fetching: $url');
      final res = await http.get(url).timeout(const Duration(seconds: 15));
      debugPrint('[DirectionsService] status: ${res.statusCode}');
      if (res.statusCode != 200) {
        debugPrint('[DirectionsService] body: ${res.body}');
        return [];
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final routes = data['routes'] as List?;
      if (routes == null || routes.isEmpty) {
        debugPrint('[DirectionsService] no routes returned');
        return [];
      }
      final points = (routes[0]['geometry']['coordinates'] as List)
          .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
          .toList();
      debugPrint('[DirectionsService] got ${points.length} points');
      return points;
    } catch (e) {
      debugPrint('[DirectionsService] error: $e');
      return [];
    }
  }
}

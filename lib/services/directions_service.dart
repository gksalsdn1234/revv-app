import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/revv_route.dart';
import 'mapbox_service.dart';

class DirectionsService {
  static Future<List<LatLng>> getRoute(LatLng from, LatLng to) =>
      getMultiRoute([from, to]);

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

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/revv_route.dart';
import 'mapbox_service.dart';

class DirectionsService {
  static Future<List<LatLng>> getRoute(LatLng from, LatLng to) async {
    final url = Uri.parse(
      'https://api.mapbox.com/directions/v5/mapbox/driving'
      '/${from.lng},${from.lat};${to.lng},${to.lat}'
      '?geometries=geojson&overview=full&access_token=${MapboxService.accessToken}',
    );

    try {
      final res = await http.get(url).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final routes = data['routes'] as List?;
      if (routes == null || routes.isEmpty) return [];
      final coords = (routes[0]['geometry']['coordinates'] as List)
          .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
          .toList();
      return coords;
    } catch (_) {
      return [];
    }
  }
}

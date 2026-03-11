import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import '../models/poi.dart';

class PoiService {
  static const _overpassUrl = 'https://overpass-api.de/api/interpreter';

  static Future<List<Poi>> search(
    double lat,
    double lng,
    PoiCategory category, {
    int radiusM = 5000,
    int maxResults = 8,
  }) async {
    final q = '''
[out:json][timeout:15];
(
  node["${category.osmKey}"="${category.osmValue}"](around:$radiusM,$lat,$lng);
);
out body $maxResults;
''';

    try {
      final res = await http
          .post(Uri.parse(_overpassUrl), body: {'data': q})
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return [];

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final elements = data['elements'] as List;

      final pois = elements.map((e) {
        final eLat = (e['lat'] as num).toDouble();
        final eLng = (e['lon'] as num).toDouble();
        final tags = e['tags'] as Map<String, dynamic>? ?? {};
        final name = (tags['name'] as String?) ??
            (tags['name:en'] as String?) ??
            category.label;
        return Poi(
          name: name,
          lat: eLat,
          lng: eLng,
          category: category,
          distanceKm: _haversine(lat, lng, eLat, eLng),
        );
      }).toList();

      pois.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
      return pois;
    } catch (_) {
      return [];
    }
  }

  static double _haversine(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * r * math.asin(math.sqrt(a));
  }

  static double _rad(double deg) => deg * math.pi / 180;
}

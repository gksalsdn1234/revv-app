import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/revv_route.dart';

class RegionPhotoService {
  static const Duration cacheTtl = Duration(days: 30);

  final http.Client _client;
  final SharedPreferences? _prefs;
  final DateTime Function() _now;
  final Map<String, Future<String?>> _inFlight = {};

  RegionPhotoService({
    http.Client? client,
    SharedPreferences? prefs,
    DateTime Function()? now,
  }) : _client = client ?? http.Client(),
       _prefs = prefs,
       _now = now ?? DateTime.now;

  Future<String?> photoUrl({required String geohash4, required LatLng point}) {
    return _inFlight.putIfAbsent(
      geohash4,
      () => _loadPhotoUrl(geohash4: geohash4, point: point),
    );
  }

  Future<String?> _loadPhotoUrl({
    required String geohash4,
    required LatLng point,
  }) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final cacheKey = 'region_photo:$geohash4';
    final cached = prefs.getString(cacheKey);
    final cachedAt = prefs.getInt('$cacheKey:ts');
    if (cached != null &&
        cachedAt != null &&
        _now().difference(DateTime.fromMillisecondsSinceEpoch(cachedAt)) <
            cacheTtl) {
      return cached;
    }

    try {
      final searchUri = Uri.https('commons.wikimedia.org', '/w/api.php', {
        'action': 'query',
        'list': 'geosearch',
        'gscoord': '${point.lat}|${point.lng}',
        'gsradius': '10000',
        'gsnamespace': '6',
        'gslimit': '5',
        'format': 'json',
      });
      final search = await _client.get(searchUri);
      if (search.statusCode != 200) return null;
      final searchJson = jsonDecode(search.body) as Map<String, dynamic>;
      final images =
          (searchJson['query'] as Map<String, dynamic>?)?['geosearch']
              as List<dynamic>?;
      if (images == null || images.isEmpty) return null;
      final title = (images.first as Map<String, dynamic>)['title'] as String?;
      if (title == null || title.isEmpty) return null;

      final imageUri = Uri.https('commons.wikimedia.org', '/w/api.php', {
        'action': 'query',
        'titles': title,
        'prop': 'imageinfo',
        'iiprop': 'url',
        'iiurlwidth': '480',
        'format': 'json',
      });
      final image = await _client.get(imageUri);
      if (image.statusCode != 200) return null;
      final imageJson = jsonDecode(image.body) as Map<String, dynamic>;
      final pages =
          (imageJson['query'] as Map<String, dynamic>?)?['pages']
              as Map<String, dynamic>?;
      if (pages == null || pages.isEmpty) return null;
      final imageInfo =
          (pages.values.first as Map<String, dynamic>)['imageinfo']
              as List<dynamic>?;
      final thumbUrl = imageInfo?.isEmpty ?? true
          ? null
          : (imageInfo!.first as Map<String, dynamic>)['thumburl'] as String?;
      if (thumbUrl == null || thumbUrl.isEmpty) return null;

      await prefs.setString(cacheKey, thumbUrl);
      await prefs.setInt('$cacheKey:ts', _now().millisecondsSinceEpoch);
      return thumbUrl;
    } catch (_) {
      return null;
    }
  }
}

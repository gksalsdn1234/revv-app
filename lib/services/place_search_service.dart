import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/revv_route.dart';
import 'mapbox_service.dart';

class PlaceResult {
  final String name;
  final String address;
  final LatLng point;

  const PlaceResult({
    required this.name,
    required this.address,
    required this.point,
  });
}

class PlaceSearchService {
  static const _requestTimeout = Duration(seconds: 8);

  final http.Client _client;
  final Map<String, List<PlaceResult>> _cache = {};

  PlaceSearchService({http.Client? client}) : _client = client ?? http.Client();

  bool get isEnabled => MapboxService.isConfigured;

  Future<List<PlaceResult>> searchPlaces(
    String query, {
    LatLng? proximity,
    String language = 'en',
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty || !isEnabled) return const [];

    final safeLanguage = _safeLanguage(language);
    final key = _cacheKey(trimmed, proximity, safeLanguage);
    final cached = _cache[key];
    if (cached != null) return cached;

    try {
      final response = await _client
          .get(_forwardUri(trimmed, proximity, safeLanguage))
          .timeout(_requestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const [];
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return const [];
      final results = parseMapboxGeocodingPlaces(decoded);
      _cache[key] = results;
      return results;
    } on TimeoutException {
      return const [];
    } catch (_) {
      return const [];
    }
  }

  Uri _forwardUri(String query, LatLng? proximity, String language) {
    return Uri.https('api.mapbox.com', '/search/geocode/v6/forward', {
      'q': query,
      'limit': '6',
      'language': language,
      if (proximity != null) 'proximity': '${proximity.lng},${proximity.lat}',
      'access_token': MapboxService.accessToken,
    });
  }
}

List<PlaceResult> parseMapboxGeocodingPlaces(Map<String, dynamic> json) {
  final features = json['features'];
  if (features is! List) return const [];

  final results = <PlaceResult>[];
  for (final feature in features) {
    if (feature is! Map<String, dynamic>) continue;
    final properties = feature['properties'];
    if (properties is! Map<String, dynamic>) continue;

    final point = _parsePoint(feature, properties);
    if (point == null) continue;

    final name = (properties['name'] as String?)?.trim();
    final address =
        (properties['full_address'] as String?)?.trim() ??
        (properties['place_formatted'] as String?)?.trim() ??
        '';
    if (name == null || name.isEmpty) continue;

    results.add(PlaceResult(name: name, address: address, point: point));
  }
  return results;
}

LatLng? _parsePoint(
  Map<String, dynamic> feature,
  Map<String, dynamic> properties,
) {
  final coordinates = properties['coordinates'];
  if (coordinates is Map<String, dynamic>) {
    final lat = (coordinates['latitude'] as num?)?.toDouble();
    final lng = (coordinates['longitude'] as num?)?.toDouble();
    if (lat != null && lng != null) return LatLng(lat, lng);
  }

  final geometry = feature['geometry'];
  if (geometry is Map<String, dynamic>) {
    final raw = geometry['coordinates'];
    if (raw is List && raw.length >= 2) {
      return LatLng((raw[1] as num).toDouble(), (raw[0] as num).toDouble());
    }
  }

  return null;
}

String _safeLanguage(String language) {
  return switch (language.toLowerCase()) {
    'ko' || 'en' || 'fr' => language.toLowerCase(),
    _ => 'en',
  };
}

String _cacheKey(String query, LatLng? proximity, String language) {
  final normalized = query.trim().toLowerCase();
  final point = proximity == null
      ? 'none'
      : '${proximity.lat.toStringAsFixed(4)},${proximity.lng.toStringAsFixed(4)}';
  return '$normalized|$point|$language';
}

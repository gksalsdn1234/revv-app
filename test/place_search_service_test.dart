import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/services/place_search_service.dart';

void main() {
  test('Mapbox Geocoding parser reads place names addresses and points', () {
    final json = jsonDecode(_geocodingFixture) as Map<String, dynamic>;

    final results = parseMapboxGeocodingPlaces(json);

    expect(results, hasLength(2));
    expect(results.first.name, 'Circuit Gilles-Villeneuve');
    expect(
      results.first.address,
      'Circuit Gilles-Villeneuve, Montreal, Quebec',
    );
    expect(results.first.point.lat, 45.5001);
    expect(results.first.point.lng, -73.5229);
    expect(results.first.featureType, 'poi');
    expect(results.first.isArea, isFalse);
    expect(results.last.name, 'Mount Royal Park');
    expect(results.last.address, 'Montreal, Quebec, Canada');
    expect(results.last.point.lat, 45.5048);
    expect(results.last.point.lng, -73.5878);
  });

  test('search returns empty results when Mapbox token is missing', () async {
    final service = PlaceSearchService();

    final results = await service.searchPlaces('Montreal');

    expect(results, isEmpty);
    expect(service.isEnabled, isFalse);
  });

  test('Mapbox Geocoding parser caps retained results', () {
    final features = List.generate(
      50,
      (index) => {
        'properties': {
          'name': 'Place $index',
          'coordinates': {'longitude': -73.0, 'latitude': 45.0},
        },
      },
    );

    final results = parseMapboxGeocodingPlaces({'features': features});

    expect(results, hasLength(6));
  });
}

const _geocodingFixture = '''
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "properties": {
        "name": "Circuit Gilles-Villeneuve",
        "feature_type": "poi",
        "full_address": "Circuit Gilles-Villeneuve, Montreal, Quebec",
        "coordinates": {
          "longitude": -73.5229,
          "latitude": 45.5001
        }
      },
      "geometry": {
        "type": "Point",
        "coordinates": [-73.5229, 45.5001]
      }
    },
    {
      "type": "Feature",
      "properties": {
        "name": "Mount Royal Park",
        "place_formatted": "Montreal, Quebec, Canada"
      },
      "geometry": {
        "type": "Point",
        "coordinates": [-73.5878, 45.5048]
      }
    }
  ]
}
''';

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/services/transit_eta_service.dart';

void main() {
  test('fallback ETA applies road detour factor and 60kmh baseline', () {
    const waypoints = [LatLng(0, 0), LatLng(0, 1)];

    final legs = fallbackLegs(waypoints);

    expect(legs, hasLength(1));
    expect(legs.first.distanceKm, closeTo(144.6, 0.8));
    expect(legs.first.estimatedMinutes, 145);
    expect(legs.first.usesFallbackGeometry, isTrue);
  });

  test(
    'Mapbox Directions parser reads per-leg distance duration and geometry',
    () {
      const waypoints = [
        LatLng(45.0, -73.0),
        LatLng(45.1, -73.1),
        LatLng(45.2, -73.2),
      ];
      final json = jsonDecode(_directionsFixture) as Map<String, dynamic>;

      final legs = parseMapboxDirectionsLegs(json, waypoints);

      expect(legs, isNotNull);
      expect(legs, hasLength(2));
      expect(legs!.first.distanceKm, 12.4);
      expect(legs.first.estimatedMinutes, 15);
      expect(legs.first.usesFallbackGeometry, isFalse);
      expect(legs.first.nodes.length, 3);
      expect(legs.last.distanceKm, 8.1);
      expect(legs.last.estimatedMinutes, 10);
    },
  );
}

const _directionsFixture = '''
{
  "routes": [
    {
      "legs": [
        {
          "distance": 12400,
          "duration": 900,
          "steps": [
            {
              "geometry": {
                "type": "LineString",
                "coordinates": [[-73.0, 45.0], [-73.05, 45.05]]
              }
            }
          ]
        },
        {
          "distance": 8100,
          "duration": 620,
          "steps": [
            {
              "geometry": {
                "type": "LineString",
                "coordinates": [[-73.1, 45.1], [-73.2, 45.2]]
              }
            }
          ]
        }
      ]
    }
  ]
}
''';

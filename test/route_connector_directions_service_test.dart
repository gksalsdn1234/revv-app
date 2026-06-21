import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/services/route_connector_directions_service.dart';

void main() {
  test('parseDirectionsGeometry reads full Mapbox route geometry', () {
    final geometry = RouteConnectorDirectionsService.parseDirectionsGeometry(
      jsonEncode({
        'routes': [
          {
            'distance': 1840.0,
            'geometry': {
              'type': 'LineString',
              'coordinates': [
                [-73.0000, 45.0000],
                [-72.9900, 45.0100],
                [-72.9800, 45.0200],
              ],
            },
          },
        ],
      }),
    );

    expect(geometry.distanceKm, closeTo(1.84, 0.001));
    expect(geometry.nodes.length, 3);
    expect(geometry.nodes.first.lat, 45.0000);
    expect(geometry.nodes.first.lng, -73.0000);
    expect(geometry.nodes.last.lat, 45.0200);
    expect(geometry.nodes.last.lng, -72.9800);
  });

  test('parseDirectionsGeometry returns empty geometry for missing routes', () {
    final geometry = RouteConnectorDirectionsService.parseDirectionsGeometry(
      jsonEncode({'routes': []}),
    );

    expect(geometry.distanceKm, 0);
    expect(geometry.nodes, isEmpty);
  });
}

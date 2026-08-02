import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/widgets/map_widget.dart';

void main() {
  test(
    'buildPolylineGeoJson creates a MultiLineString without joining parts',
    () {
      final geoJson =
          jsonDecode(
                buildPolylineGeoJson([
                  const [LatLng(1, 2), LatLng(3, 4)],
                  const [LatLng(5, 6), LatLng(7, 8)],
                ]),
              )
              as Map<String, Object?>;

      expect(geoJson['type'], 'Feature');
      final geometry = geoJson['geometry'] as Map<String, Object?>;
      expect(geometry['type'], 'MultiLineString');
      expect(geometry['coordinates'], [
        [
          [2.0, 1.0],
          [4.0, 3.0],
        ],
        [
          [6.0, 5.0],
          [8.0, 7.0],
        ],
      ]);
    },
  );

  test('buildPolylineGeoJson keeps single polyline geometry unchanged', () {
    final geoJson =
        jsonDecode(
              buildPolylineGeoJson([
                const [LatLng(1, 2), LatLng(3, 4)],
              ]),
            )
            as Map<String, Object?>;

    final geometry = geoJson['geometry'] as Map<String, Object?>;
    expect(geometry['type'], 'LineString');
    expect(geometry['coordinates'], [
      [2.0, 1.0],
      [4.0, 3.0],
    ]);
  });

  test('active curve heatmap covers both segments touching a sharp curve node', () {
    const nodes = [
      LatLng(45.000000, -73.000000),
      LatLng(45.000000, -72.999900),
      LatLng(45.000010, -72.999900),
      LatLng(45.000020, -72.999900),
      LatLng(45.000030, -72.999900),
    ];

    final buckets = buildCurveHeatmapSegments(nodes);

    // Node 1 is the sharp, unevenly spaced bend. Its tight bucket must start
    // one segment before the node and end one segment after it.
    expect(buckets[3], [
      [nodes[0], nodes[1], nodes[2]],
    ]);
    expect(buckets[0], [
      [nodes[2], nodes[3]],
    ]);
  });
}

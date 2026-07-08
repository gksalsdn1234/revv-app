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
}

import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/services/route_geometry_matcher.dart';

void main() {
  test('downsampleForMatching keeps endpoints and respects max points', () {
    final nodes = List.generate(
      220,
      (i) => LatLng(45.0 + i * 0.001, -73.0 - i * 0.001),
    );

    final sampled = RouteGeometryMatcher.downsampleForMatching(
      nodes,
      maxPoints: 90,
    );

    expect(sampled.length, lessThanOrEqualTo(90));
    expect(sampled.first.lat, nodes.first.lat);
    expect(sampled.first.lng, nodes.first.lng);
    expect(sampled.last.lat, nodes.last.lat);
    expect(sampled.last.lng, nodes.last.lng);
  });

  test('parseMatchedGeometry reads Mapbox geojson coordinates as LatLng', () {
    const raw = '''
{
  "code": "Ok",
  "matchings": [
    {
      "geometry": {
        "type": "LineString",
        "coordinates": [
          [-73.600000, 45.500000],
          [-73.610000, 45.510000]
        ]
      }
    }
  ]
}
''';

    final nodes = RouteGeometryMatcher.parseMatchedGeometry(raw);

    expect(nodes, hasLength(2));
    expect(nodes.first.lat, 45.5);
    expect(nodes.first.lng, -73.6);
    expect(nodes.last.lat, 45.51);
    expect(nodes.last.lng, -73.61);
  });

  test(
    'parseMatchedGeometry returns empty when matching body has no geometry',
    () {
      final nodes = RouteGeometryMatcher.parseMatchedGeometry(
        '{"code":"NoMatch","matchings":[]}',
      );

      expect(nodes, isEmpty);
    },
  );

  test('parseMatchedGeometry caps retained coordinates', () {
    final coordinates = List.generate(6000, (i) => [-73.0, 45.0 + i / 100000]);
    final raw =
        '{"matchings":[{"geometry":{"coordinates":${coordinates.toString()}}}]}';

    final nodes = RouteGeometryMatcher.parseMatchedGeometry(raw);

    expect(nodes, hasLength(5000));
  });
}

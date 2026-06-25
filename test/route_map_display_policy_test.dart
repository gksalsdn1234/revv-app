import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/ui/route_map_display_policy.dart';

void main() {
  test('route finder map keeps the full visual route field', () {
    final mapRoutes = List.generate(12, _route);
    final visibleRoutes = mapRoutes.take(3).toList();

    final displayRoutes = routeFinderMapDisplayRoutes(
      mapVisualRoutes: mapRoutes,
      visibleRoutes: visibleRoutes,
    );

    expect(displayRoutes, hasLength(12));
    expect(displayRoutes.map((route) => route.id), [
      for (var i = 0; i < 12; i++) 'route-$i',
    ]);
  });

  test(
    'route finder map falls back to recommendations before field is ready',
    () {
      final visibleRoutes = List.generate(3, _route);

      final displayRoutes = routeFinderMapDisplayRoutes(
        mapVisualRoutes: const [],
        visibleRoutes: visibleRoutes,
      );

      expect(displayRoutes, visibleRoutes);
    },
  );
}

RevvRoute _route(int index) {
  final lat = 37.0 + index * 0.01;
  final lng = -122.0 - index * 0.01;
  return RevvRoute(
    id: 'route-$index',
    name: 'Route $index',
    nodes: [LatLng(lat, lng), LatLng(lat + 0.004, lng - 0.004)],
    distanceKm: 12 + index.toDouble(),
    windingScore: 4.5,
    starRating: 4,
    sharpCurveCount: 8,
    centerPoint: LatLng(lat + 0.002, lng - 0.002),
    distanceFromUser: index.toDouble(),
  );
}

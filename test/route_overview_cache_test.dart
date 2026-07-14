import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/services/route_overview_cache.dart';

RevvRoute _cachedRoute() {
  const center = LatLng(49.2827, -123.1207);
  return const RevvRoute(
    id: 'cached-overview',
    name: 'Cached overview',
    nodes: [center, LatLng(49.32, -123.08)],
    distanceKm: 12,
    windingScore: 7,
    starRating: 4,
    sharpCurveCount: 8,
    centerPoint: center,
    distanceFromUser: 0,
    tightCurveKm: 2,
    mediumCurveKm: 3,
    maxContinuousKm: 1.5,
  );
}

void main() {
  test('route overview cache restores a fresh compressed field', () async {
    // Given: a temporary application directory and a national map field.
    final directory = await Directory.systemTemp.createTemp('revv-overview-');
    addTearDown(() => directory.delete(recursive: true));
    final cache = RouteOverviewCache(directoryProvider: () async => directory);
    final routes = [_cachedRoute()];

    // When: the field is persisted and read on the next load.
    await cache.write(
      RouteOverviewCacheEntry(
        routes: routes,
        completedRegionKeys: const {'49.2827,-123.1207'},
      ),
    );
    final restored = await cache.read();

    // Then: map geometry is available without another network response.
    expect(restored?.routes.map((route) => route.id), ['cached-overview']);
    expect(restored?.completedRegionKeys, {'49.2827,-123.1207'});
    expect(
      await File('${directory.path}/route_overview_v1.json.gz').exists(),
      isTrue,
    );
  });
}

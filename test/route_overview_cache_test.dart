import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/services/route_overview_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

RevvRoute _cachedRoute({
  String id = 'cached-overview',
  String name = 'Cached overview',
}) {
  const center = LatLng(49.2827, -123.1207);
  return RevvRoute(
    id: id,
    name: name,
    nodes: const [center, LatLng(49.32, -123.08)],
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

String _deterministicNoise(int seed, int length) {
  var state = seed;
  return String.fromCharCodes(
    List<int>.generate(length, (_) {
      state = (state * 1103515245 + 12345) & 0x7fffffff;
      return 33 + ((state >> 8) % 94);
    }, growable: false),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('route overview cache restores through default app storage', () async {
    final cache = RouteOverviewCache();

    await cache.write(
      RouteOverviewCacheEntry(
        routes: [_cachedRoute()],
        completedRegionKeys: const {'49.2827,-123.1207'},
        regionHadRoutes: const {'49.2827,-123.1207': true},
      ),
    );
    final restored = await RouteOverviewCache().read();

    expect(restored?.routes.map((route) => route.id), ['cached-overview']);
  });

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
        regionHadRoutes: const {'49.2827,-123.1207': true},
      ),
    );
    final restored = await cache.read();

    // Then: map geometry is available without another network response.
    expect(restored?.routes.map((route) => route.id), ['cached-overview']);
    expect(restored?.completedRegionKeys, {'49.2827,-123.1207'});
    expect(restored?.regionHadRoutes, {'49.2827,-123.1207': true});
    expect(
      await File('${directory.path}/route_overview_v1.json.gz').exists(),
      isTrue,
    );
  });

  test(
    'route overview cache truncates incompressible input below 2 MB',
    () async {
      final directory = await Directory.systemTemp.createTemp('revv-overview-');
      addTearDown(() => directory.delete(recursive: true));
      final cache = RouteOverviewCache(
        directoryProvider: () async => directory,
      );

      await cache.write(
        RouteOverviewCacheEntry(
          routes: [
            for (var index = 0; index < RouteOverviewCache.maxRoutes; index++)
              _cachedRoute(
                id: 'large-$index',
                name: _deterministicNoise(index + 1, 6000),
              ),
          ],
          completedRegionKeys: const {'49.2827,-123.1207'},
          regionHadRoutes: const {'49.2827,-123.1207': true},
        ),
      );

      final file = File('${directory.path}/route_overview_v1.json.gz');
      final restored = await cache.read();

      expect(
        await file.length(),
        lessThanOrEqualTo(RouteOverviewCache.maxCompressedBytes),
      );
      expect(restored, isNotNull);
      expect(restored!.routes.length, inInclusiveRange(1, 649));
    },
  );

  test('route overview cache rejects corrupt gzip without throwing', () async {
    final directory = await Directory.systemTemp.createTemp('revv-overview-');
    addTearDown(() => directory.delete(recursive: true));
    final cache = RouteOverviewCache(directoryProvider: () async => directory);
    final file = File('${directory.path}/route_overview_v1.json.gz');
    await file.writeAsBytes(const [0x52, 0x45, 0x56, 0x56], flush: true);

    expect(await cache.read(), isNull);
  });
}

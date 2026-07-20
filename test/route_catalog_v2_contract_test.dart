import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/core/storage_keys.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/services/route_loading_policy.dart';
import 'package:revv_app/services/route_overview_cache.dart';
import 'package:revv_app/services/route_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef _CatalogFetcher = Future<List<RevvRoute>> Function(int maxResults);
typedef _EpochFetcher = Future<int> Function();
typedef _FieldFetcher =
    Future<List<RevvRoute>> Function(LatLng center, int maxResults);
typedef _NodeFetcher = Future<List<LatLng>> Function(String routeId);

RevvRoute _route(
  String id,
  LatLng center, {
  bool generated = false,
  DateTime? activatedAt,
  bool withNodes = true,
  required String contract,
}) {
  final named = <Symbol, dynamic>{
    #id: id,
    #name: 'Contract $id',
    #nodes: withNodes
        ? [center, LatLng(center.lat + 0.01, center.lng + 0.01)]
        : <LatLng>[],
    #distanceKm: 12.0,
    #windingScore: 7.0,
    #starRating: 4,
    #sharpCurveCount: 8,
    #centerPoint: center,
    #distanceFromUser: 0.0,
    if (generated) #isGenerated: true,
    if (generated) #activatedAt: activatedAt,
  };
  try {
    return Function.apply(RevvRoute.new, const [], named) as RevvRoute;
  } catch (error) {
    fail(
      '$contract requires RevvRoute(isGenerated, activatedAt) constructor '
      'metadata; constructor rejected the injectable fixture '
      '(${error.runtimeType}).',
    );
  }
}

dynamic _routeService({
  required String contract,
  RouteOverviewCache? overviewCache,
  RouteOverviewFetcher? viewportFetcher,
  _CatalogFetcher? catalogFetcher,
  _EpochFetcher? epochFetcher,
  _FieldFetcher? localV2Fetcher,
  _FieldFetcher? legacyFetcher,
  _NodeFetcher? nodeV2Fetcher,
  _NodeFetcher? legacyNodeFetcher,
}) {
  final named = <Symbol, dynamic>{
    #routeOverviewCache: ?overviewCache,
    #routeOverviewFetcher: ?viewportFetcher,
    #routeCatalogFetcher: ?catalogFetcher,
    #routeCatalogEpochFetcher: ?epochFetcher,
    #routeLocalV2Fetcher: ?localV2Fetcher,
    #routeLegacyFetcher: ?legacyFetcher,
    #routeNodeV2Fetcher: ?nodeV2Fetcher,
    #routeLegacyNodeFetcher: ?legacyNodeFetcher,
  };
  try {
    return Function.apply(RouteService.new, const [], named);
  } catch (error) {
    fail(
      '$contract requires injectable RouteService constructor seams; '
      'constructor rejected the fake contract (${error.runtimeType}).',
    );
  }
}

RouteOverviewCacheEntry _overviewEntry({
  required List<RevvRoute> routes,
  required int catalogEpoch,
  required String contract,
}) {
  final completedKeys = routeOverviewCenters.map(_regionKey).toSet();
  try {
    return Function.apply(RouteOverviewCacheEntry.new, const [], {
          #routes: routes,
          #completedRegionKeys: completedKeys,
          #regionHadRoutes: {for (final key in completedKeys) key: true},
          #catalogEpoch: catalogEpoch,
        })
        as RouteOverviewCacheEntry;
  } catch (error) {
    fail(
      '$contract requires RouteOverviewCacheEntry.catalogEpoch; '
      'constructor rejected the epoch-bound fixture (${error.runtimeType}).',
    );
  }
}

String _regionKey(LatLng center) =>
    '${center.lat.toStringAsFixed(4)},${center.lng.toStringAsFixed(4)}';

Map<String, dynamic> _localCacheJson({
  required LatLng center,
  required List<RevvRoute> routes,
  required int catalogEpoch,
}) => {
  'version': 3,
  'centerLat': center.lat,
  'centerLng': center.lng,
  'radiusKm': RouteService.routeFieldRadiusKm,
  'fetchedAt': DateTime.now().toIso8601String(),
  'catalogEpoch': catalogEpoch,
  'routes': routes.map((route) => route.toJson()).toList(),
};

Future<Directory> _temporaryDirectory(String prefix) =>
    Directory.systemTemp.createTemp(prefix);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'RED behavior: cold overview makes one catalog RPC capped at 650',
    () async {
      const contract = 'one-request <=650 catalog';
      final directory = await _temporaryDirectory('revv-catalog-one-request-');
      addTearDown(() => directory.delete(recursive: true));
      var epochCalls = 0;
      var catalogCalls = 0;
      var requestedLimit = 0;
      final service = _routeService(
        contract: contract,
        overviewCache: RouteOverviewCache(
          directoryProvider: () async => directory,
        ),
        epochFetcher: () async {
          epochCalls++;
          return 7;
        },
        catalogFetcher: (maxResults) async {
          catalogCalls++;
          requestedLimit = maxResults;
          return [
            for (var index = 0; index < maxResults; index++)
              _route(
                'catalog-$index',
                LatLng(49.0 + index / 10000, -123),
                contract: contract,
              ),
          ];
        },
        viewportFetcher: (center, maxResults) async => const [],
      );
      addTearDown(service.dispose as void Function());

      await service.prefetchRouteOverview(routeOverviewCenters.first);

      expect(epochCalls, 1);
      expect(catalogCalls, 1);
      expect(requestedLimit, inInclusiveRange(1, 650));
      expect((service.mapVisualRoutes as List).length, lessThanOrEqualTo(650));
    },
  );

  test(
    'RED behavior: successful epoch validation and catalog load are reused in session',
    () async {
      const contract = 'same-session epoch and catalog reuse';
      final directory = await _temporaryDirectory('revv-catalog-epoch-reuse-');
      addTearDown(() => directory.delete(recursive: true));
      var epochCalls = 0;
      var catalogCalls = 0;
      final service = _routeService(
        contract: contract,
        overviewCache: RouteOverviewCache(
          directoryProvider: () async => directory,
        ),
        epochFetcher: () async {
          epochCalls++;
          return 11;
        },
        catalogFetcher: (maxResults) async {
          catalogCalls++;
          return [
            _route(
              'catalog-once',
              routeOverviewCenters.first,
              contract: contract,
            ),
          ];
        },
        viewportFetcher: (center, maxResults) async => const [],
      );
      addTearDown(service.dispose as void Function());

      await service.prefetchRouteOverview(routeOverviewCenters.first);
      await service.prefetchRouteOverview(routeOverviewCenters.first);

      expect(epochCalls, 1);
      expect(catalogCalls, 1);
    },
  );

  test(
    'RED behavior: generated metadata and epoch round-trip through overview cache',
    () async {
      const contract = 'overview generated metadata round-trip';
      final directory = await _temporaryDirectory('revv-generated-overview-');
      addTearDown(() => directory.delete(recursive: true));
      final activatedAt = DateTime.utc(2026, 7, 16, 4, 30);
      final cache = RouteOverviewCache(
        directoryProvider: () async => directory,
      );
      await cache.write(
        _overviewEntry(
          routes: [
            _route(
              'generated-overview',
              routeOverviewCenters.first,
              generated: true,
              activatedAt: activatedAt,
              contract: contract,
            ),
          ],
          catalogEpoch: 9,
          contract: contract,
        ),
      );

      final dynamic restored = await cache.read();
      final dynamic route = restored.routes.single;
      expect(restored.catalogEpoch, 9);
      expect(route.isGenerated, isTrue);
      expect(route.activatedAt, activatedAt);
    },
  );

  test(
    'RED behavior: validated generated metadata round-trips through local cache',
    () async {
      const contract = 'local generated metadata round-trip';
      final center = routeOverviewCenters.first;
      final activatedAt = DateTime.utc(2026, 7, 16, 4, 30);
      final generated = _route(
        'generated-local',
        center,
        generated: true,
        activatedAt: activatedAt,
        contract: contract,
      );
      SharedPreferences.setMockInitialValues({
        StorageKeys.routeCache: jsonEncode(
          _localCacheJson(center: center, routes: [generated], catalogEpoch: 9),
        ),
      });
      var epochCalls = 0;
      final service = _routeService(
        contract: contract,
        epochFetcher: () async {
          epochCalls++;
          return 9;
        },
      );
      addTearDown(service.dispose as void Function());

      await service.prefetchRouteField(center.lat, center.lng);

      final dynamic restored = (service.rawCandidateRoutes as List).single;
      expect(epochCalls, 1);
      expect(restored.isGenerated, isTrue);
      expect(restored.activatedAt, activatedAt);
    },
  );

  test('generated NEW window is strict at the 30-day boundary', () {
    const contract = 'strict generated 30-day window';
    final activatedAt = DateTime.utc(2026, 7, 1, 12);
    final route = _route(
      'generated-new-window',
      routeOverviewCenters.first,
      generated: true,
      activatedAt: activatedAt,
      contract: contract,
    );

    expect(
      route.isNewlyGeneratedAt(
        activatedAt
            .add(const Duration(days: 30))
            .subtract(const Duration(microseconds: 1)),
      ),
      isTrue,
    );
    expect(
      route.isNewlyGeneratedAt(activatedAt.add(const Duration(days: 30))),
      isFalse,
    );
  });

  test('overview cache is capped at 650 routes and 2 MB compressed', () async {
    const contract = 'bounded compressed overview cache';
    final directory = await _temporaryDirectory('revv-overview-bounds-');
    addTearDown(() => directory.delete(recursive: true));
    final cache = RouteOverviewCache(directoryProvider: () async => directory);
    await cache.write(
      _overviewEntry(
        routes: [
          for (var index = 0; index < 651; index++)
            _route(
              'bounded-$index',
              LatLng(49 + index / 10000, -123),
              contract: contract,
            ),
        ],
        catalogEpoch: 3,
        contract: contract,
      ),
    );

    final restored = await cache.read();
    final file = File('${directory.path}/route_overview_v1.json.gz');
    expect(restored, isNotNull);
    expect(restored!.routes.length, 650);
    expect(await file.length(), lessThanOrEqualTo(2 * 1024 * 1024));
  });

  test('RED behavior: offline local cache strips generated rows', () async {
    const contract = 'offline generated local-cache stripping';
    final center = routeOverviewCenters.first;
    final routes = [
      _route('legacy-local', center, contract: contract),
      _route(
        'generated-local',
        center,
        generated: true,
        activatedAt: DateTime.utc(2026, 7, 16),
        contract: contract,
      ),
    ];
    SharedPreferences.setMockInitialValues({
      StorageKeys.routeCache: jsonEncode(
        _localCacheJson(center: center, routes: routes, catalogEpoch: 4),
      ),
    });
    final service = _routeService(
      contract: contract,
      epochFetcher: () async => throw const SocketException('offline'),
    );
    addTearDown(service.dispose as void Function());

    await service.prefetchRouteField(center.lat, center.lng);

    expect((service.rawCandidateRoutes as List).map((route) => route.id), [
      'legacy-local',
    ]);
  });

  test(
    'RED behavior: failed epoch validation strips generated overview cache',
    () async {
      const contract = 'failed epoch generated overview-cache stripping';
      final directory = await _temporaryDirectory('revv-failed-epoch-');
      addTearDown(() => directory.delete(recursive: true));
      final cache = RouteOverviewCache(
        directoryProvider: () async => directory,
      );
      await cache.write(
        _overviewEntry(
          routes: [
            _route(
              'legacy-overview',
              routeOverviewCenters.first,
              contract: contract,
            ),
            _route(
              'generated-overview',
              routeOverviewCenters.first,
              generated: true,
              activatedAt: DateTime.utc(2026, 7, 16),
              contract: contract,
            ),
          ],
          catalogEpoch: 5,
          contract: contract,
        ),
      );
      final service = _routeService(
        contract: contract,
        overviewCache: cache,
        epochFetcher: () async => throw TimeoutException('epoch timeout'),
        catalogFetcher: (maxResults) async =>
            throw TimeoutException('catalog timeout'),
        viewportFetcher: (center, maxResults) async => const [],
      );
      addTearDown(service.dispose as void Function());

      await service.prefetchRouteOverview(routeOverviewCenters.first);

      expect((service.mapVisualRoutes as List).map((route) => route.id), [
        'legacy-overview',
      ]);
    },
  );

  test(
    'RED behavior: changed epoch after disable strips stale generated overview',
    () async {
      const contract = 'disabled-batch epoch invalidation';
      final directory = await _temporaryDirectory('revv-disabled-epoch-');
      addTearDown(() => directory.delete(recursive: true));
      final cache = RouteOverviewCache(
        directoryProvider: () async => directory,
      );
      final legacy = _route(
        'legacy-after-disable',
        routeOverviewCenters.first,
        contract: contract,
      );
      await cache.write(
        _overviewEntry(
          routes: [
            legacy,
            _route(
              'disabled-generated',
              routeOverviewCenters.first,
              generated: true,
              activatedAt: DateTime.utc(2026, 7, 16),
              contract: contract,
            ),
          ],
          catalogEpoch: 7,
          contract: contract,
        ),
      );
      final service = _routeService(
        contract: contract,
        overviewCache: cache,
        epochFetcher: () async => 8,
        catalogFetcher: (maxResults) async => [legacy],
        viewportFetcher: (center, maxResults) async => const [],
      );
      addTearDown(service.dispose as void Function());

      await service.prefetchRouteOverview(routeOverviewCenters.first);

      final ids = (service.mapVisualRoutes as List)
          .map((route) => route.id)
          .toList();
      expect(ids, contains('legacy-after-disable'));
      expect(ids, isNot(contains('disabled-generated')));
    },
  );

  test('RED behavior: v2 timeout fallback exposes legacy rows only', () async {
    const contract = 'legacy-only v2 fallback';
    final center = routeOverviewCenters.first;
    final legacy = _route('legacy-fallback', center, contract: contract);
    final generated = _route(
      'generated-must-not-fallback',
      center,
      generated: true,
      activatedAt: DateTime.utc(2026, 7, 16),
      contract: contract,
    );
    var v2Calls = 0;
    var legacyCalls = 0;
    final service = _routeService(
      contract: contract,
      epochFetcher: () async => 3,
      localV2Fetcher: (requestCenter, maxResults) async {
        v2Calls++;
        throw TimeoutException('v2 timeout');
      },
      legacyFetcher: (requestCenter, maxResults) async {
        legacyCalls++;
        return [legacy, generated];
      },
    );
    addTearDown(service.dispose as void Function());

    await service.prefetchRouteField(
      center.lat,
      center.lng,
      forceRefresh: true,
    );

    expect(v2Calls, 1);
    expect(legacyCalls, 1);
    expect((service.rawCandidateRoutes as List).map((route) => route.id), [
      'legacy-fallback',
    ]);
  });

  test(
    'RED behavior: node-v2 timeout falls back only for legacy route',
    () async {
      const contract = 'legacy-only node-v2 fallback';
      final center = routeOverviewCenters.first;
      final legacy = _route(
        'legacy-node',
        center,
        withNodes: false,
        contract: contract,
      );
      final generated = _route(
        'generated-node',
        center,
        generated: true,
        activatedAt: DateTime.utc(2026, 7, 16),
        withNodes: false,
        contract: contract,
      );
      var legacyNodeCalls = 0;
      final service = _routeService(
        contract: contract,
        nodeV2Fetcher: (routeId) async =>
            throw TimeoutException('node timeout'),
        legacyNodeFetcher: (routeId) async {
          legacyNodeCalls++;
          return [center, LatLng(center.lat + 0.01, center.lng + 0.01)];
        },
      );
      addTearDown(service.dispose as void Function());

      dynamic hydratedLegacy;
      dynamic hydratedGenerated;
      try {
        hydratedLegacy = await service.hydrateRouteNodes(legacy);
        hydratedGenerated = await service.hydrateRouteNodes(generated);
      } catch (error) {
        fail(
          '$contract requires a public injectable hydrateRouteNodes seam '
          '(${error.runtimeType}).',
        );
      }

      expect((hydratedLegacy.nodes as List), hasLength(2));
      expect((hydratedGenerated.nodes as List), isEmpty);
      expect(legacyNodeCalls, 1);
    },
  );

  test('current local recommendation fetch boundary is 120', () {
    expect(RouteService.routeFieldInitialFetchLimit, 120);
  });

  test('current viewport supplement requests never exceed 30', () async {
    final directory = await _temporaryDirectory('revv-viewport-limit-');
    addTearDown(() => directory.delete(recursive: true));
    final requestedLimits = <int>[];
    final service = RouteService(
      routeOverviewCache: RouteOverviewCache(
        directoryProvider: () async => directory,
      ),
      routeOverviewFetcher: (center, maxResults) async {
        requestedLimits.add(maxResults);
        return const [];
      },
    );
    addTearDown(service.dispose);

    await service.prefetchRouteOverview(routeOverviewCenters.first);

    expect(requestedLimits, hasLength(1));
    expect(requestedLimits.every((limit) => limit <= 30), isTrue);
  });

  test('current viewport supplement concurrency never exceeds three', () async {
    final directory = await _temporaryDirectory('revv-viewport-concurrency-');
    addTearDown(() => directory.delete(recursive: true));
    final gate = Completer<void>();
    var active = 0;
    var peak = 0;
    final service = RouteService(
      routeOverviewCache: RouteOverviewCache(
        directoryProvider: () async => directory,
      ),
      routeOverviewFetcher: (center, maxResults) async {
        active++;
        peak = active > peak ? active : peak;
        await gate.future;
        active--;
        return const [];
      },
    );
    addTearDown(service.dispose);

    final loading = service.prefetchRouteOverview(routeOverviewCenters.first);
    for (var attempt = 0; attempt < 50 && peak == 0; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    if (!gate.isCompleted) gate.complete();
    await loading;
    expect(peak, lessThanOrEqualTo(3));
    expect(peak, greaterThan(0));
  });

  test('current merged overview and local field never exceed 650', () async {
    const contract = 'current global 650 cap';
    final directory = await _temporaryDirectory('revv-global-limit-');
    addTearDown(() => directory.delete(recursive: true));
    final local = [
      for (var index = 0; index < 120; index++)
        _route(
          'local-cap-$index',
          routeOverviewCenters.first,
          contract: contract,
        ),
    ];
    final service =
        RouteService(
            routeOverviewCache: RouteOverviewCache(
              directoryProvider: () async => directory,
            ),
            routeOverviewFetcher: (center, maxResults) async => [
              for (var index = 0; index < maxResults; index++)
                _route(
                  'overview-cap-${center.lat}-${center.lng}-$index',
                  center,
                  contract: contract,
                ),
            ],
          )
          ..rawCandidateRoutes = local
          ..mapVisualRoutes = local;
    addTearDown(service.dispose);

    await service.prefetchRouteOverview(routeOverviewCenters.first);

    expect(service.mapVisualRoutes.length, lessThanOrEqualTo(650));
    expect(service.mapVisualRoutes.length, greaterThan(local.length));
  });

  test(
    'RED behavior: catalog timeout still schedules the latest panned viewport',
    () async {
      const contract = 'catalog timeout latest-viewport preservation';
      final directory = await _temporaryDirectory('revv-catalog-timeout-');
      addTearDown(() => directory.delete(recursive: true));
      final catalogGate = Completer<void>();
      var catalogCalls = 0;
      final requestedViewports = <LatLng>[];
      final service = _routeService(
        contract: contract,
        overviewCache: RouteOverviewCache(
          directoryProvider: () async => directory,
        ),
        epochFetcher: () async => 12,
        catalogFetcher: (maxResults) async {
          catalogCalls++;
          await catalogGate.future;
          throw TimeoutException('catalog timeout');
        },
        viewportFetcher: (center, maxResults) async {
          requestedViewports.add(center);
          return [_route('viewport-${center.lat}', center, contract: contract)];
        },
      );
      addTearDown(service.dispose as void Function());

      final initial =
          service.prefetchRouteOverview(routeOverviewCenters.first)
              as Future<void>;
      for (var attempt = 0; attempt < 20 && catalogCalls == 0; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      const latestViewport = LatLng(47.5615, -52.7126);
      await service.prefetchRouteOverview(latestViewport);
      catalogGate.complete();
      await initial;
      for (
        var attempt = 0;
        attempt < 20 && !requestedViewports.contains(latestViewport);
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }

      expect(catalogCalls, 1);
      expect(requestedViewports, contains(latestViewport));
      expect(
        (service.mapVisualRoutes as List).map((route) => route.id),
        contains('viewport-${latestViewport.lat}'),
      );
    },
  );
}

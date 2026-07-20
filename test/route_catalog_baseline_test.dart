import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/core/storage_keys.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/services/route_loading_policy.dart';
import 'package:revv_app/services/route_overview_cache.dart';
import 'package:revv_app/services/route_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

RevvRoute _route(String id, LatLng center) {
  return RevvRoute(
    id: id,
    name: 'Baseline $id',
    nodes: [center, LatLng(center.lat + 0.01, center.lng + 0.01)],
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

String _regionKey(LatLng center) =>
    '${center.lat.toStringAsFixed(4)},${center.lng.toStringAsFixed(4)}';

void main() {
  test(
    'current one-catalog plus viewport flow records bounded loading and cache metrics',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'revv-catalog-baseline-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final localCenter = routeOverviewCenters.first;
      final localRoutes = [
        for (
          var index = 0;
          index < RouteService.routeFieldInitialFetchLimit;
          index++
        )
          _route('local-$index', localCenter),
      ];
      SharedPreferences.setMockInitialValues({
        StorageKeys.routeCache: jsonEncode({
          'version': 2,
          'centerLat': localCenter.lat,
          'centerLng': localCenter.lng,
          'radiusKm': RouteService.routeFieldRadiusKm,
          'fetchedAt': DateTime.now().toIso8601String(),
          'routes': localRoutes.map((route) => route.toJson()).toList(),
        }),
      });

      var catalogRpcRequests = 0;
      var viewportRpcRequests = 0;
      var activeRequests = 0;
      var peakConcurrency = 0;
      var simulatedCatalogPayloadBytes = 0;
      var simulatedViewportPayloadBytes = 0;
      var requestedCatalogLimit = 0;
      var requestedViewportLimit = 0;
      final cache = RouteOverviewCache(
        directoryProvider: () async => directory,
      );
      final service = RouteService(
        routeOverviewCache: cache,
        routeCatalogEpochFetcher: () async => 7,
        routeCatalogFetcher: (maxResults) async {
          catalogRpcRequests++;
          requestedCatalogLimit = maxResults;
          activeRequests++;
          peakConcurrency = activeRequests > peakConcurrency
              ? activeRequests
              : peakConcurrency;
          await Future<void>.delayed(const Duration(milliseconds: 1));
          final routes = [
            for (var index = 0; index < maxResults; index++)
              _route(
                'catalog-$index',
                LatLng(localCenter.lat + index / 10000, localCenter.lng),
              ),
          ];
          simulatedCatalogPayloadBytes = utf8
              .encode(
                jsonEncode(routes.map((route) => route.toJson()).toList()),
              )
              .length;
          activeRequests--;
          return routes;
        },
        routeOverviewFetcher: (center, maxResults) async {
          viewportRpcRequests++;
          requestedViewportLimit = maxResults;
          activeRequests++;
          peakConcurrency = activeRequests > peakConcurrency
              ? activeRequests
              : peakConcurrency;
          await Future<void>.delayed(const Duration(milliseconds: 1));
          final routes = [
            for (var index = 0; index < maxResults; index++)
              _route(
                'overview-${center.lat}-${center.lng}-$index',
                LatLng(center.lat + index / 10000, center.lng),
              ),
          ];
          simulatedViewportPayloadBytes = utf8
              .encode(
                jsonEncode(routes.map((route) => route.toJson()).toList()),
              )
              .length;
          activeRequests--;
          return routes;
        },
      );
      addTearDown(service.dispose);

      final rssBefore = ProcessInfo.currentRss;
      final localStopwatch = Stopwatch()..start();
      await service.prefetchRouteField(localCenter.lat, localCenter.lng);
      localStopwatch.stop();
      final firstLocalFieldLatencyMs = localStopwatch.elapsedMilliseconds;
      expect(
        service.rawCandidateRoutes,
        hasLength(RouteService.routeFieldInitialFetchLimit),
      );

      final overviewStopwatch = Stopwatch()..start();
      await service.prefetchRouteOverview(localCenter);
      overviewStopwatch.stop();
      final rssAfter = ProcessInfo.currentRss;

      final cacheFile = File('${directory.path}/route_overview_v1.json.gz');
      final compressedBytes = await cacheFile.readAsBytes();
      final decodedBytes = gzip.decode(compressedBytes);
      final cached = await cache.read();

      expect(catalogRpcRequests, 1);
      expect(viewportRpcRequests, 1);
      expect(requestedCatalogLimit, RouteService.routeFieldFetchLimit);
      expect(requestedViewportLimit, RouteService.routeOverviewPerRegionLimit);
      expect(peakConcurrency, lessThanOrEqualTo(1));
      expect(cached?.routes, hasLength(RouteService.routeFieldFetchLimit));
      expect(service.mapVisualRoutes.length, RouteService.routeFieldFetchLimit);
      expect(RouteService.routeFieldInitialFetchLimit, 120);
      expect(RouteService.routeOverviewPerRegionLimit, 30);
      expect(RouteService.routeFieldFetchLimit, 650);
      expect(compressedBytes.length, lessThanOrEqualTo(2 * 1024 * 1024));

      final metrics = <String, Object>{
        'baseline': 'current_one_catalog_plus_viewport',
        'catalog_rpc_request_count': catalogRpcRequests,
        'viewport_rpc_request_count': viewportRpcRequests,
        'total_data_rpc_request_count':
            catalogRpcRequests + viewportRpcRequests,
        'catalog_request_limit': requestedCatalogLimit,
        'viewport_request_limit': requestedViewportLimit,
        'catalog_route_count': RouteService.routeFieldFetchLimit,
        'viewport_route_count': RouteService.routeOverviewPerRegionLimit,
        'final_map_route_count': service.mapVisualRoutes.length,
        'local_recommendation_fetch_limit':
            RouteService.routeFieldInitialFetchLimit,
        'viewport_supplement_limit': RouteService.routeOverviewPerRegionLimit,
        'global_catalog_cache_limit': RouteService.routeFieldFetchLimit,
        'peak_concurrency': peakConcurrency,
        'simulated_catalog_rpc_payload_bytes': simulatedCatalogPayloadBytes,
        'simulated_viewport_rpc_payload_bytes': simulatedViewportPayloadBytes,
        'simulated_rpc_payload_bytes':
            simulatedCatalogPayloadBytes + simulatedViewportPayloadBytes,
        'compressed_cache_bytes': compressedBytes.length,
        'decoded_cache_bytes': decodedBytes.length,
        'first_local_cached_field_latency_ms': firstLocalFieldLatencyMs,
        'total_background_latency_ms': overviewStopwatch.elapsedMilliseconds,
        'rss_snapshot_before_bytes': rssBefore,
        'rss_snapshot_after_bytes': rssAfter,
      };
      // ignore: avoid_print
      print('WESTERN_ROUTE_BASELINE ${jsonEncode(metrics)}');
    },
  );

  test('current overview cache fails closed on corrupt gzip data', () async {
    final directory = await Directory.systemTemp.createTemp(
      'revv-corrupt-overview-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final cache = RouteOverviewCache(directoryProvider: () async => directory);
    await File(
      '${directory.path}/route_overview_v1.json.gz',
    ).writeAsBytes(const [0, 1, 2, 3, 4]);

    expect(await cache.read(), isNull);
  });

  test(
    'current fresh complete cache avoids a duplicate offline viewport request',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'revv-complete-overview-',
      );
      addTearDown(() => directory.delete(recursive: true));
      SharedPreferences.setMockInitialValues({});
      final cache = RouteOverviewCache(
        directoryProvider: () async => directory,
      );
      await cache.write(
        RouteOverviewCacheEntry(
          routes: [_route('legacy-cache', routeOverviewCenters.first)],
          completedRegionKeys: routeOverviewCenters.map(_regionKey).toSet(),
          regionHadRoutes: {
            for (final center in routeOverviewCenters)
              _regionKey(center): center == routeOverviewCenters.first,
          },
        ),
      );
      var requests = 0;
      final service = RouteService(
        routeOverviewCache: cache,
        routeOverviewFetcher: (center, maxResults) async {
          requests++;
          return const [];
        },
      );
      addTearDown(service.dispose);

      await service.prefetchRouteOverview(routeOverviewCenters.first);
      await service.prefetchRouteOverview(routeOverviewCenters.first);

      expect(requests, 0);
      expect(service.mapVisualRoutes.map((route) => route.id), [
        'legacy-cache',
      ]);
    },
  );
}

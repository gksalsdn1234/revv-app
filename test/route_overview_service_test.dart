import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/services/route_loading_policy.dart';
import 'package:revv_app/services/route_overview_cache.dart';
import 'package:revv_app/services/route_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

RevvRoute _overviewRoute(String id, LatLng center) {
  return RevvRoute(
    id: id,
    name: 'Overview $id',
    nodes: [center, LatLng(center.lat + 0.05, center.lng + 0.05)],
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
  test(
    'route overview loads every launch region with a bounded result count',
    () async {
      SharedPreferences.setMockInitialValues({});
      final requestedCenters = <LatLng>[];
      var requestIndex = 0;
      final service = RouteService(
        routeOverviewFetcher: (center, maxResults) async {
          expect(maxResults, 30);
          expect(maxResults, RouteService.routeOverviewPerRegionLimit);
          requestedCenters.add(center);
          return [_overviewRoute('region-${requestIndex++}', center)];
        },
      );
      addTearDown(service.dispose);

      await service.prefetchRouteOverview(routeCoverageCenters.first);

      expect(requestedCenters.toSet(), routeOverviewCenters.toSet());
      expect(requestedCenters.first, routeCoverageCenters.first);
      expect(service.mapVisualRoutes, hasLength(routeOverviewCenters.length));
      expect(service.routeOverviewLoaded, isTrue);
    },
  );

  test(
    'uncovered viewport is requested before national sample regions',
    () async {
      SharedPreferences.setMockInitialValues({});
      final directory = await Directory.systemTemp.createTemp('revv-overview-');
      addTearDown(() => directory.delete(recursive: true));
      final requestedCenters = <LatLng>[];
      const viewportCenter = LatLng(47.0, -82.0);
      final service = RouteService(
        routeOverviewCache: RouteOverviewCache(
          directoryProvider: () async => directory,
        ),
        routeOverviewFetcher: (center, _) async {
          requestedCenters.add(center);
          return [_overviewRoute('route-${center.lat}-${center.lng}', center)];
        },
      );
      addTearDown(service.dispose);

      await service.prefetchRouteOverview(viewportCenter);

      expect(requestedCenters.first, viewportCenter);
      expect(requestedCenters.toSet(), {
        viewportCenter,
        ...routeOverviewCenters,
      });
      expect(service.routeOverviewLoaded, isTrue);
    },
  );

  test('completed national overview loads a newly panned viewport', () async {
    SharedPreferences.setMockInitialValues({});
    final directory = await Directory.systemTemp.createTemp('revv-overview-');
    addTearDown(() => directory.delete(recursive: true));
    final requestedCenters = <LatLng>[];
    final service = RouteService(
      routeOverviewCache: RouteOverviewCache(
        directoryProvider: () async => directory,
      ),
      routeOverviewFetcher: (center, _) async {
        requestedCenters.add(center);
        return [_overviewRoute('route-${center.lat}-${center.lng}', center)];
      },
    );
    addTearDown(service.dispose);

    await service.prefetchRouteOverview(routeOverviewCenters.first);
    expect(service.routeOverviewLoaded, isTrue);
    requestedCenters.clear();

    const newViewport = LatLng(47.5615, -52.7126);
    await service.prefetchRouteOverview(newViewport);

    expect(requestedCenters, [newViewport]);
    expect(service.routeOverviewLoaded, isTrue);
    expect(
      service.mapVisualRoutes.any(
        (route) => route.id == 'route-${newViewport.lat}-${newViewport.lng}',
      ),
      isTrue,
    );
  });

  test('nearby pan reuses completed overview coverage', () async {
    SharedPreferences.setMockInitialValues({});
    final directory = await Directory.systemTemp.createTemp('revv-overview-');
    addTearDown(() => directory.delete(recursive: true));
    final requestedCenters = <LatLng>[];
    final service = RouteService(
      routeOverviewCache: RouteOverviewCache(
        directoryProvider: () async => directory,
      ),
      routeOverviewFetcher: (center, _) async {
        requestedCenters.add(center);
        return const [];
      },
    );
    addTearDown(service.dispose);

    await service.prefetchRouteOverview(routeOverviewCenters.first);
    requestedCenters.clear();

    await service.prefetchRouteOverview(const LatLng(49.3, -123.1));

    expect(requestedCenters, isEmpty);
  });

  test(
    'latest viewport is loaded after an in-flight national request',
    () async {
      SharedPreferences.setMockInitialValues({});
      final directory = await Directory.systemTemp.createTemp('revv-overview-');
      addTearDown(() => directory.delete(recursive: true));
      final gate = Completer<void>();
      final requestedCenters = <LatLng>[];
      var waitForGate = true;
      final service = RouteService(
        routeOverviewCache: RouteOverviewCache(
          directoryProvider: () async => directory,
        ),
        routeOverviewFetcher: (center, _) async {
          requestedCenters.add(center);
          if (waitForGate) await gate.future;
          return [_overviewRoute('route-${center.lat}-${center.lng}', center)];
        },
      );
      addTearDown(service.dispose);

      final initialLoad = service.prefetchRouteOverview(
        routeOverviewCenters.first,
      );
      await Future<void>.delayed(Duration.zero);
      const latestViewport = LatLng(47.5615, -52.7126);
      await service.prefetchRouteOverview(latestViewport);
      waitForGate = false;
      gate.complete();
      await initialLoad;
      for (
        var attempt = 0;
        attempt < 20 && !requestedCenters.contains(latestViewport);
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(requestedCenters.last, latestViewport);
    },
  );

  test('national overview does not overwrite local loading status', () async {
    SharedPreferences.setMockInitialValues({});
    final service =
        RouteService(
            routeOverviewFetcher: (center, _) async => [
              _overviewRoute('overview-${center.lat}-${center.lng}', center),
            ],
          )
          ..routeDataSourceLabel = 'Supabase'
          ..routeDataStatusTitle = '루트 준비 완료'
          ..routeDataStatusBody = '주변 추천이 준비됐습니다.'
          ..backgroundStatusMessage = null;
    addTearDown(service.dispose);

    await service.prefetchRouteOverview(routeOverviewCenters.first);

    expect(service.routeDataSourceLabel, 'Supabase');
    expect(service.routeDataStatusTitle, '루트 준비 완료');
    expect(service.routeDataStatusBody, '주변 추천이 준비됐습니다.');
    expect(service.backgroundStatusMessage, isNull);
  });

  test('route overview shows the first completed region immediately', () async {
    // Given: every national sample request is still pending.
    SharedPreferences.setMockInitialValues({});
    final first = Completer<List<RevvRoute>>();
    final remaining = Completer<List<RevvRoute>>();
    LatLng? firstCenter;
    final service = RouteService(
      routeOverviewFetcher: (center, _) {
        if (firstCenter == null) {
          firstCenter = center;
          return first.future;
        }
        return remaining.future;
      },
    );
    addTearDown(service.dispose);

    // When: only the first region finishes.
    final loading = service.prefetchRouteOverview(routeCoverageCenters.first);
    await Future<void>.delayed(Duration.zero);
    first.complete([_overviewRoute('first-ready', firstCenter!)]);
    await Future<void>.delayed(Duration.zero);

    // Then: its route is visible without waiting for the other regions.
    expect(service.mapVisualRoutes.map((route) => route.id), ['first-ready']);
    expect(service.routeOverviewLoading, isTrue);

    remaining.complete(const []);
    await loading;
  });

  test('route overview limits background request concurrency', () async {
    // Given: every regional request waits on the same gate.
    SharedPreferences.setMockInitialValues({});
    final gate = Completer<void>();
    var activeRequests = 0;
    var peakRequests = 0;
    final service = RouteService(
      routeOverviewFetcher: (center, _) async {
        activeRequests++;
        peakRequests = activeRequests > peakRequests
            ? activeRequests
            : peakRequests;
        await gate.future;
        activeRequests--;
        return const [];
      },
    );
    addTearDown(service.dispose);

    // When: the national background load starts.
    final loading = service.prefetchRouteOverview(routeCoverageCenters.first);
    await Future<void>.delayed(Duration.zero);

    // Then: it does not compete with the foreground using all 13 requests.
    expect(peakRequests, 3);
    gate.complete();
    await loading;
  });

  test('fresh national cache skips duplicate background requests', () async {
    // Given: a fresh compressed national field already exists on disk.
    SharedPreferences.setMockInitialValues({});
    final directory = await Directory.systemTemp.createTemp('revv-overview-');
    addTearDown(() => directory.delete(recursive: true));
    final cache = RouteOverviewCache(directoryProvider: () async => directory);
    final cachedRoute = _overviewRoute(
      'cached-national',
      routeOverviewCenters.first,
    );
    await cache.write(
      RouteOverviewCacheEntry(
        routes: [cachedRoute],
        completedRegionKeys: {
          for (final center in routeOverviewCenters)
            '${center.lat.toStringAsFixed(4)},${center.lng.toStringAsFixed(4)}',
        },
      ),
    );
    var networkRequests = 0;
    final service = RouteService(
      routeOverviewCache: cache,
      routeOverviewFetcher: (center, _) async {
        networkRequests++;
        return const [];
      },
    );
    addTearDown(service.dispose);

    // When: the overview is requested again within its cache TTL.
    await service.prefetchRouteOverview(routeCoverageCenters.first);

    // Then: cached geometry is reused without another national fan-out.
    expect(networkRequests, 0);
    expect(service.mapVisualRoutes.map((route) => route.id), [
      'cached-national',
    ]);
    expect(service.routeOverviewLoaded, isTrue);
  });

  test('partial national cache retries only regions that failed', () async {
    // Given: one regional request fails while the other regions are cached.
    SharedPreferences.setMockInitialValues({});
    final directory = await Directory.systemTemp.createTemp('revv-overview-');
    addTearDown(() => directory.delete(recursive: true));
    final cache = RouteOverviewCache(directoryProvider: () async => directory);
    final failedCenter = routeOverviewCenters.last;
    final firstPassRequests = <LatLng>[];
    final firstService = RouteService(
      routeOverviewCache: cache,
      routeOverviewFetcher: (center, _) async {
        firstPassRequests.add(center);
        if (center == failedCenter) throw TimeoutException('regional timeout');
        return [_overviewRoute('first-${center.lat}-${center.lng}', center)];
      },
    );

    await firstService.prefetchRouteOverview(routeOverviewCenters.first);
    firstService.dispose();
    expect(firstPassRequests.toSet(), routeOverviewCenters.toSet());

    // When: the overview is loaded again from the partial cache.
    final retryRequests = <LatLng>[];
    final secondService = RouteService(
      routeOverviewCache: cache,
      routeOverviewFetcher: (center, _) async {
        retryRequests.add(center);
        return [_overviewRoute('retry-${center.lat}-${center.lng}', center)];
      },
    );
    addTearDown(secondService.dispose);
    await secondService.prefetchRouteOverview(routeOverviewCenters.first);

    // Then: successful cached regions stay local and only the timeout retries.
    expect(retryRequests, [failedCenter]);
    expect(secondService.routeOverviewLoaded, isTrue);
    expect(
      secondService.mapVisualRoutes.any(
        (route) => route.id == 'retry-${failedCenter.lat}-${failedCenter.lng}',
      ),
      isTrue,
    );
  });

  test(
    'partial national load retries missing regions in the same session',
    () async {
      SharedPreferences.setMockInitialValues({});
      final failedCenter = routeOverviewCenters.last;
      var shouldFail = true;
      final requests = <LatLng>[];
      final service = RouteService(
        routeOverviewFetcher: (center, _) async {
          requests.add(center);
          if (center == failedCenter && shouldFail) {
            throw TimeoutException('regional timeout');
          }
          return [_overviewRoute('route-${center.lat}-${center.lng}', center)];
        },
      );
      addTearDown(service.dispose);

      await service.prefetchRouteOverview(routeOverviewCenters.first);
      expect(service.routeOverviewLoaded, isFalse);

      shouldFail = false;
      requests.clear();
      await service.prefetchRouteOverview(routeOverviewCenters.first);

      expect(requests, [failedCenter]);
      expect(service.routeOverviewLoaded, isTrue);
    },
  );

  test('national map routes do not replace local recommendations', () async {
    // Given: a local recommendation is already selected.
    SharedPreferences.setMockInitialValues({});
    final localCenter = routeCoverageCenters.first;
    final localRoute = _overviewRoute('local', localCenter);
    final service =
        RouteService(
            routeOverviewFetcher: (center, _) async => [
              _overviewRoute('overview-${center.lat}-${center.lng}', center),
            ],
          )
          ..rawCandidateRoutes = [localRoute]
          ..routes = [localRoute]
          ..selectedRoute = localRoute
          ..mapVisualRoutes = [localRoute];
    addTearDown(service.dispose);

    // When: the national map field finishes loading.
    await service.prefetchRouteOverview(localCenter);

    // Then: the recommendation remains local while map-only routes expand.
    expect(service.routes.map((route) => route.id), ['local']);
    expect(service.selectedRoute?.id, 'local');
    expect(service.mapVisualRoutes.length, greaterThan(1));
  });
}

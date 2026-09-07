import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase/supabase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/services/route_performance.dart';
import 'package:revv_app/services/route_overview_transport.dart';
import 'package:revv_app/services/latest_work_queue.dart';
import 'package:revv_app/services/route_service.dart';
import 'package:revv_app/services/route_loading_policy.dart';
import 'package:revv_app/services/supabase_service.dart';
import 'package:revv_app/services/drive_planner_service.dart';

const route = RevvRoute(
  id: 'perf',
  name: 'Winding',
  nodes: [LatLng(45, -73), LatLng(45.01, -73)],
  distanceKm: 12,
  windingScore: 40,
  starRating: 4,
  sharpCurveCount: 4,
  centerPoint: LatLng(45, -73),
  distanceFromUser: 0,
);
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => RoutePerformance.observer = null);
  test(
    'HTTP timing counts bytes without leaking request or response data',
    () async {
      final events = <String, Map<String, num>>{};
      RoutePerformance.observer = (stage, data) => events[stage] = data;
      final client = RouteTimingClient(
        MockClient((_) async => http.Response('secret', 200)),
      );
      addTearDown(client.close);
      final r = await client.post(
        Uri.parse('https://example.invalid/rest/v1/rpc/find_curvy_roads_v2'),
        body: 'private coordinate',
      );
      expect(r.body, 'secret');
      expect(events['rpc.find_curvy_roads_v2.body']!['bytes'], 6);
      expect(jsonEncode(events), isNot(contains('secret')));
      expect(events.keys, hasLength(2));
    },
  );
  test(
    'overview rollout falls back once only when new RPC is absent',
    () async {
      final calls = <String>[];
      final transport = RouteOverviewTransport((name, _) async {
        calls.add(name);
        if (name == 'new') {
          throw const PostgrestException(message: 'missing', code: 'PGRST202');
        }
        return [];
      });
      await transport.request('new', 'old', {});
      await transport.request('new', 'old', {});
      expect(calls, ['new', 'old', 'old']);
    },
  );
  test(
    'overview never hides authorization or timeout errors with legacy calls',
    () async {
      var calls = 0;
      final transport = RouteOverviewTransport((name, _) async {
        calls++;
        throw const PostgrestException(message: 'denied', code: '42501');
      });
      await expectLater(
        transport.request('new', 'old', {}),
        throwsA(isA<PostgrestException>()),
      );
      expect(calls, 1);
    },
  );
  test('overview geometry marker survives storage and row parsing', () {
    final restored = RevvRoute.fromJson(
      route.copyWith(geometryIsOverview: true).toJson(),
    );
    expect(restored.geometryIsOverview, isTrue);
    final parsed = SupabaseService.routeFromRow({
      'id': 'p',
      'nodes': [
        {'lat': 45, 'lng': -73},
        {'lat': 45.01, 'lng': -73},
      ],
      'geometry_detail': 'overview',
    });
    expect(parsed.geometryIsOverview, isTrue);
    expect(route.geometryIsOverview, isFalse);
  });
  test(
    'selected overview is hydrated even when it already contains nodes',
    () async {
      var calls = 0;
      final service = RouteService(
        routeNodeV2Fetcher: (_) async {
          calls++;
          return [const LatLng(45, -73), const LatLng(45.02, -73)];
        },
      );
      addTearDown(service.dispose);
      final full = await service.hydrateRouteNodes(
        route.copyWith(geometryIsOverview: true),
      );
      expect(calls, 1);
      expect(full.geometryIsOverview, isFalse);
      expect(full.distanceKm, 12);
    },
  );
  test(
    'generated overview failing detail never crosses legacy boundary',
    () async {
      var legacy = 0;
      final service = RouteService(
        routeNodeV2Fetcher: (_) async => [],
        routeLegacyNodeFetcher: (_) async {
          legacy++;
          return route.nodes;
        },
      );
      addTearDown(service.dispose);
      final full = await service.hydrateRouteNodes(
        route.copyWith(isGenerated: true, geometryIsOverview: true),
      );
      expect(full.geometryIsOverview, isTrue);
      expect(legacy, 0);
    },
  );
  test(
    'planner rejects overview when authoritative nodes are unavailable',
    () async {
      final planner = DrivePlannerService(nodesLoader: (_) async => []);
      await expectLater(
        planner.buildPlanFromRoutes(
          origin: route.centerPoint,
          routes: [route.copyWith(geometryIsOverview: true)],
        ),
        throwsStateError,
      );
    },
  );
  test(
    'nearby request starts while epoch is pending but does not publish early',
    () async {
      final epoch = Completer<int>();
      final nearby = Completer<void>();
      final service = RouteService(
        routeCatalogEpochFetcher: () => epoch.future,
        routeLocalV2Fetcher: (_, _) async {
          nearby.complete();
          return [route.copyWith(isGenerated: true, catalogEpoch: 7)];
        },
      );
      addTearDown(service.dispose);
      final fetch = service.prefetchRouteField(45, -73);
      await nearby.future;
      expect(service.rawCandidateRoutes, isEmpty);
      epoch.complete(7);
      await fetch;
      expect(service.rawCandidateRoutes, hasLength(1));
    },
  );
  test(
    'simultaneous preview and start share the authoritative detail request',
    () async {
      final gate = Completer<List<LatLng>>();
      var calls = 0;
      final service = RouteService(
        routeNodeV2Fetcher: (_) {
          calls++;
          return gate.future;
        },
      );
      addTearDown(service.dispose);
      final overview = route.copyWith(geometryIsOverview: true);
      final a = service.hydrateRouteNodes(overview);
      final b = service.hydrateRouteNodes(overview);
      expect(calls, 1);
      gate.complete(route.nodes);
      expect((await a).geometryIsOverview, isFalse);
      expect((await b).geometryIsOverview, isFalse);
    },
  );
  test(
    'budget composites resolve source routes instead of querying a synthetic id',
    () async {
      RevvRoute part(String id, double lat) => route.copyWith(
        id: id,
        name: 'Route $id',
        nodes: [LatLng(lat, -73), LatLng(lat + 0.05, -73)],
        centerPoint: LatLng(lat + 0.025, -73),
        distanceKm: 18,
        windingScore: 6.4,
        sharpCurveCount: 8,
        tightCurveKm: 2.0,
        mediumCurveKm: 2.5,
        maxContinuousKm: 1.4,
        geometryIsOverview: true,
      );
      final a = part('a', 45);
      final b = part('b', 45.053);
      final combo = combineRouteChainGeometry([a, b]);
      expect(combo, isNotNull);
      expect(combo!.geometryIsOverview, isTrue);
      final requested = <String>[];
      final service = RouteService(
        routeNodeV2Fetcher: (id) async {
          requested.add(id);
          return id == 'a' ? a.nodes : b.nodes;
        },
      );
      addTearDown(service.dispose);
      final full = await service.hydrateRouteNodes(
        RevvRoute.fromJson(combo.toJson()),
      );
      expect(full.geometryIsOverview, isFalse);
      expect(requested, unorderedEquals(['a', 'b']));
      expect(full.nodes.length, greaterThanOrEqualTo(4));
    },
  );
  test('map queue retains current and newest state only', () async {
    final queue = LatestWorkQueue<int>();
    final gate = Completer<void>();
    final calls = <int>[];
    Future<void> work(int value) async {
      calls.add(value);
      if (value == 1) await gate.future;
    }

    final a = queue.submit(1, work);
    final b = queue.submit(2, work);
    final c = queue.submit(3, work);
    gate.complete();
    await Future.wait([a, b, c]);
    expect(calls, [1, 3]);
  });
  test('map queue can continue after failed update', () async {
    final queue = LatestWorkQueue<int>();
    await expectLater(
      queue.submit(1, (_) async => throw StateError('style changed')),
      throwsStateError,
    );
    var latest = 0;
    await queue.submit(2, (n) async => latest = n);
    expect(latest, 2);
  });
  test(
    'retained sources create once, update data and skip unchanged state',
    () async {
      final sources = RetainedRouteSources();
      var creates = 0;
      var updates = 0;
      Future<void> put(String data) => sources.put(
        'lines',
        data,
        create: () async {
          creates++;
        },
        update: () async {
          updates++;
        },
      );
      await put('first');
      await put('second');
      await put('second');
      expect(creates, 1);
      expect(updates, 1);
      sources.reset();
      await put('second');
      expect(creates, 2);
    },
  );
  test(
    'style reset during create does not mark new style as initialized',
    () async {
      final sources = RetainedRouteSources();
      final gate = Completer<void>();
      final pending = sources.put(
        'lines',
        'data',
        create: () => gate.future,
        update: () async {},
      );
      sources.reset();
      gate.complete();
      await pending;
      expect(sources.contains('lines'), isFalse);
    },
  );
}

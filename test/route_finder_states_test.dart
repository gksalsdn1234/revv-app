import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/core/app_language.dart';
import 'package:provider/provider.dart';
import 'package:revv_app/models/drive_plan.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/screens/lean_route_finder_screen.dart';
import 'package:revv_app/services/drive_planner_service.dart';
import 'package:revv_app/services/location_service.dart';
import 'package:revv_app/services/route_loading_policy.dart';
import 'package:revv_app/services/route_service.dart';
import 'package:revv_app/services/settings_service.dart';
import 'package:revv_app/services/supabase_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const forbiddenWords = ['MAX', 'BEST', 'PEAK', '어택', '스릴', '경쟁'];

  Future<void> pumpStateCard(
    WidgetTester tester,
    RouteFinderStateKind kind, {
    VoidCallback? onAction,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RouteFinderStateCard(
            kind: kind,
            language: AppLanguage.korean,
            onAction: onAction ?? () {},
          ),
        ),
      ),
    );
  }

  Future<void> pumpCoverageCard(
    WidgetTester tester, {
    bool requested = false,
    bool requesting = false,
    VoidCallback? onRequest,
    VoidCallback? onBrowseMontreal,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RouteCoverageBoundaryCard(
            language: AppLanguage.korean,
            requested: requested,
            requesting: requesting,
            onRequest: onRequest ?? () {},
            onBrowseMontreal: onBrowseMontreal ?? () {},
          ),
        ),
      ),
    );
  }

  Future<void> pumpWithSettings(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => SettingsService(),
        child: MaterialApp(home: Scaffold(body: child)),
      ),
    );
  }

  void expectSafeCopy(List<String> values) {
    for (final value in values) {
      for (final forbidden in forbiddenWords) {
        expect(value, isNot(contains(forbidden)));
      }
    }
  }

  testWidgets('temporary location denial renders retry permission action', (
    tester,
  ) async {
    var tapped = false;

    await pumpStateCard(
      tester,
      RouteFinderStateKind.temporaryLocationDenied,
      onAction: () => tapped = true,
    );

    const expected = ['위치 권한이 꺼져 있어요', '위치 다시 허용'];
    expect(find.text(expected[0]), findsOneWidget);
    expect(find.text(expected[1]), findsOneWidget);
    expectSafeCopy(expected);

    await tester.tap(find.text(expected[1]));
    expect(tapped, isTrue);
  });

  testWidgets('permanent location denial renders settings action', (
    tester,
  ) async {
    await pumpStateCard(tester, RouteFinderStateKind.permanentlyLocationDenied);

    const expected = ['설정에서 위치 권한을 켜주세요', '설정 열기'];
    expect(find.text(expected[0]), findsOneWidget);
    expect(find.text(expected[1]), findsOneWidget);
    expectSafeCopy(expected);
  });

  testWidgets('empty routes state nudges region presets', (tester) async {
    await pumpStateCard(tester, RouteFinderStateKind.emptyRoutes);

    const expected = ['이 반경엔 아직 발견된 루트가 없어요', '지역 프리셋'];
    expect(find.text(expected[0]), findsOneWidget);
    expect(find.text(expected[1]), findsOneWidget);
    expect(find.textContaining('반경을 넓히거나'), findsOneWidget);
    expectSafeCopy(expected);
  });

  testWidgets('load failure renders retry action without backend terms', (
    tester,
  ) async {
    await pumpStateCard(tester, RouteFinderStateKind.loadFailed);

    const expected = ['루트를 불러오지 못했어요', '다시 찾기'];
    expect(find.text(expected[0]), findsOneWidget);
    expect(find.text(expected[1]), findsOneWidget);
    expect(find.textContaining('Supabase'), findsNothing);
    expect(find.textContaining('HTTP'), findsNothing);
    expectSafeCopy(expected);
  });

  testWidgets('cached routes state explains saved data and offers picks', (
    tester,
  ) async {
    await pumpStateCard(tester, RouteFinderStateKind.cachedRoutes);

    const expected = ['저장된 루트를 먼저 보여드려요', '추천 보기'];
    expect(find.text(expected[0]), findsOneWidget);
    expect(find.text(expected[1]), findsOneWidget);
    expect(find.textContaining('저장된 커브길'), findsOneWidget);
    expectSafeCopy(expected);
  });

  testWidgets(
    'coverage boundary card renders demand request and Montreal cue',
    (tester) async {
      var requestTapped = false;
      var browseTapped = false;

      await pumpCoverageCard(
        tester,
        onRequest: () => requestTapped = true,
        onBrowseMontreal: () => browseTapped = true,
      );

      const expected = ['지금은 몬트리올 일대의 루트를 제공해요', '우리 지역 알림 받기', '몬트리올 보기'];
      expect(find.text(expected[0]), findsOneWidget);
      expect(find.text(expected[1]), findsOneWidget);
      expect(find.text(expected[2]), findsOneWidget);
      expect(find.textContaining('이 지역은 준비 중'), findsOneWidget);
      expectSafeCopy(expected);

      await tester.tap(find.text(expected[1]));
      await tester.tap(find.text(expected[2]));

      expect(requestTapped, isTrue);
      expect(browseTapped, isTrue);
    },
  );

  testWidgets('coverage boundary card renders completed request state', (
    tester,
  ) async {
    await pumpCoverageCard(tester, requested: true);

    expect(find.text('알림 신청됨'), findsOneWidget);
    expect(find.text('우리 지역 알림 받기'), findsNothing);
  });

  testWidgets(
    'drive budget strip renders duration chips and changes selection',
    (tester) async {
      DriveBudget selected = DriveBudget.any;

      await pumpWithSettings(
        tester,
        StatefulBuilder(
          builder: (context, setState) => DriveBudgetChoiceStrip(
            budget: selected,
            routes: const [],
            onChanged: (value) => setState(() => selected = value),
          ),
        ),
      );

      expect(find.text('Any'), findsOneWidget);
      expect(find.text('~30 min'), findsOneWidget);
      expect(find.text('~1 hour'), findsOneWidget);
      expect(find.text('2h+'), findsOneWidget);

      await tester.tap(find.text('~30 min'));
      await tester.pump();

      expect(selected, DriveBudget.short);
    },
  );

  testWidgets('filter sheet applies lens selection to the finder overlay', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final route = RevvRoute(
      id: 'sweeper',
      name: 'Sweeper Road',
      nodes: const [LatLng(45.0, -73.0), LatLng(45.02, -73.02)],
      distanceKm: 30,
      windingScore: 5.6,
      starRating: 4,
      sharpCurveCount: 12,
      centerPoint: const LatLng(45.01, -73.01),
      distanceFromUser: 40,
      tightCurveKm: 0.2,
      mediumCurveKm: 3.0,
      maxContinuousKm: 1.8,
    );
    final routeService = RouteService()
      ..routes = [route]
      ..mapVisualRoutes = [route];

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>(
            create: (_) => SettingsService(),
          ),
          ChangeNotifierProvider<RouteService>.value(value: routeService),
          ChangeNotifierProvider<LocationService>.value(
            value: _DeniedLocationService(),
          ),
        ],
        child: const MaterialApp(home: LeanRouteFinderScreen()),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('route-finder-filter-badge')), findsNothing);

    await tester.tap(find.byKey(const Key('route-finder-filter-button')));
    await tester.pumpAndSettle();

    expect(find.text('Filters'), findsOneWidget);
    expect(find.text('Sweepers 1'), findsOneWidget);

    await tester.tap(find.text('Sweepers 1'));
    await tester.pump();

    expect(
      find.descendant(
        of: find.byKey(const Key('route-finder-filter-button')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('route duration meta renders estimate and chain segment count', (
    tester,
  ) async {
    final route = RevvRoute(
      id: 'combo:a:b',
      name: 'North + Valley',
      nodes: const [LatLng(45.0, -73.0), LatLng(45.02, -73.02)],
      distanceKm: 36,
      windingScore: 6.2,
      starRating: 4,
      sharpCurveCount: 10,
      centerPoint: const LatLng(45.01, -73.01),
      distanceFromUser: 8,
      tightCurveKm: 2,
      mediumCurveKm: 2,
      maxContinuousKm: 1.4,
    );

    await pumpWithSettings(
      tester,
      RouteDurationMeta(route: route, language: AppLanguage.korean),
    );

    expect(find.text('~46분 · 2개 코스 연결'), findsOneWidget);
  });

  testWidgets('drive budget empty card nudges other duration or radius', (
    tester,
  ) async {
    await pumpWithSettings(
      tester,
      DriveBudgetEmptyCard(language: AppLanguage.korean, onAction: () {}),
    );

    const expected = ['이 분량에 맞는 루트가 아직 없어요', '전체 분량'];
    expect(find.text(expected[0]), findsOneWidget);
    expect(find.text(expected[1]), findsOneWidget);
    expect(find.textContaining('다른 분량'), findsOneWidget);
    expect(find.textContaining('반경/지역'), findsOneWidget);
    expectSafeCopy(expected);
  });

  testWidgets('coverage request failure restores the request button', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService();
    await settings.setAppLanguage(AppLanguage.korean);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(value: settings),
          ChangeNotifierProvider<RouteService>.value(value: RouteService()),
          ChangeNotifierProvider<LocationService>.value(
            value: _OutsideCoverageLocationService(),
          ),
          ChangeNotifierProvider<SupabaseService>.value(
            value: SupabaseService(),
          ),
        ],
        child: const MaterialApp(home: LeanRouteFinderScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('우리 지역 알림 받기'), findsOneWidget);

    await tester.tap(find.text('우리 지역 알림 받기'));
    await tester.pumpAndSettle();
    expect(find.text('우리 지역 알림 받기'), findsOneWidget);
    expect(find.text('신청 중'), findsNothing);
    expect(find.textContaining('알림 신청을 저장하지 못했어요'), findsOneWidget);
  });

  testWidgets('long press enables chain drive into planner initial plan', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService();
    await settings.setAppLanguage(AppLanguage.korean);
    final first = _finderRoute(id: 'first', name: 'First Road', lng: -73.00);
    final second = _finderRoute(id: 'second', name: 'Second Road', lng: -73.20);
    final routeService = RouteService()
      ..routes = [first, second]
      ..mapVisualRoutes = [first, second];
    final planner = _ChainPlanner();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(value: settings),
          ChangeNotifierProvider<RouteService>.value(value: routeService),
          ChangeNotifierProvider<LocationService>.value(
            value: _ReadyLocationService(),
          ),
          ChangeNotifierProvider<SupabaseService>.value(
            value: SupabaseService(),
          ),
        ],
        child: MaterialApp(home: LeanRouteFinderScreen(planner: planner)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('추천 보기'));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('First Road'));
    await tester.pumpAndSettle();

    expect(find.text('1개 루트 · 총 ~8km'), findsOneWidget);
    expect(find.text('1개 더 고르세요'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Second Road'));
    await tester.pumpAndSettle();

    expect(find.text('2개 루트 · 총 ~16km'), findsOneWidget);
    expect(find.text('이어달리기'), findsOneWidget);

    await tester.tap(find.text('이어달리기'));
    await tester.pumpAndSettle();

    expect(planner.lastRouteIds, ['first', 'second']);
    expect(find.text('First Road 12분'), findsOneWidget);
    expect(find.text('Second Road 12분'), findsOneWidget);
  });

  testWidgets('chain toggle button selects routes and cancel clears chain', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService();
    await settings.setAppLanguage(AppLanguage.korean);
    final first = _finderRoute(id: 'first', name: 'First Road', lng: -73.00);
    final second = _finderRoute(id: 'second', name: 'Second Road', lng: -73.20);
    final routeService = RouteService()
      ..routes = [first, second]
      ..mapVisualRoutes = [first, second];

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(value: settings),
          ChangeNotifierProvider<RouteService>.value(value: routeService),
          ChangeNotifierProvider<LocationService>.value(
            value: _ReadyLocationService(),
          ),
          ChangeNotifierProvider<SupabaseService>.value(
            value: SupabaseService(),
          ),
        ],
        child: const MaterialApp(home: LeanRouteFinderScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('추천 보기'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chain-toggle-button')), findsOneWidget);
    expect(find.text('이어달리기 추가'), findsOneWidget);

    await tester.tap(find.byKey(const Key('chain-toggle-button')));
    await tester.pumpAndSettle();

    expect(find.text('추가됨 1'), findsOneWidget);
    expect(find.text('1개 루트 · 총 ~8km'), findsOneWidget);
    expect(find.text('1개 더 고르세요'), findsOneWidget);
    expect(find.text('◀▶로 다른 루트를 보고 추가하세요'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chain-toggle-button')));
    await tester.pumpAndSettle();

    expect(find.text('추가됨 2'), findsOneWidget);
    expect(find.text('2개 루트 · 총 ~16km'), findsOneWidget);
    expect(find.text('이어달리기'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(find.text('2개 루트 · 총 ~16km'), findsNothing);
    expect(find.text('이어달리기 추가'), findsOneWidget);
  });
}

class _DeniedLocationService extends LocationService {
  @override
  Future<void> requestPermission() async {}

  @override
  Future<void> startTracking() async {}

  @override
  Future<LatLng?> ensureLiveLocation({
    Duration timeout = const Duration(seconds: 6),
  }) async => null;
}

class _OutsideCoverageLocationService extends LocationService {
  _OutsideCoverageLocationService() {
    hasPermission = true;
  }

  @override
  Future<void> requestPermission() async {}

  @override
  Future<void> startTracking() async {}

  @override
  Future<LatLng?> ensureLiveLocation({
    Duration timeout = const Duration(seconds: 6),
  }) async => const LatLng(43.6532, -79.3832);
}

class _ReadyLocationService extends LocationService {
  _ReadyLocationService() {
    hasPermission = true;
  }

  @override
  Future<void> requestPermission() async {}

  @override
  Future<void> startTracking() async {}

  @override
  Future<LatLng?> ensureLiveLocation({
    Duration timeout = const Duration(seconds: 6),
  }) async => const LatLng(45.0, -73.0);
}

class _ChainPlanner extends DrivePlannerService {
  List<String> lastRouteIds = const [];

  _ChainPlanner()
    : super(
        candidateLoader: (_, _) async => const [],
        transitLegLoader: (_) async => const [],
      );

  @override
  Future<DrivePlan> buildPlanFromRoutes({
    required LatLng origin,
    required List<RevvRoute> routes,
    LatLng? destination,
  }) async {
    lastRouteIds = routes.map((route) => route.id).toList();
    final waypoints = <LatLng>[origin];
    final legs = <DrivePlanLeg>[];
    for (final route in routes) {
      legs.add(
        DrivePlanLeg(
          kind: DrivePlanLegKind.transit,
          nodes: [waypoints.last, route.nodes.first],
          distanceKm: 1,
          estimatedMinutes: 3,
        ),
      );
      legs.add(
        DrivePlanLeg(
          kind: DrivePlanLegKind.winding,
          nodes: route.nodes,
          distanceKm: route.distanceKm,
          estimatedMinutes: 12,
          route: route,
        ),
      );
      waypoints
        ..add(route.nodes.first)
        ..add(route.nodes.last);
    }
    final end = destination ?? waypoints.last;
    legs.add(
      DrivePlanLeg(
        kind: DrivePlanLegKind.transit,
        nodes: [waypoints.last, end],
        distanceKm: 1,
        estimatedMinutes: 3,
      ),
    );
    waypoints.add(end);
    return DrivePlan(
      legs: legs,
      totalMinutes: routes.length * 15 + 3,
      windingMinutes: routes.length * 12,
      transitMinutes: routes.length * 3 + 3,
      waypoints: waypoints,
    );
  }
}

RevvRoute _finderRoute({
  required String id,
  required String name,
  required double lng,
}) {
  return RevvRoute(
    id: id,
    name: name,
    nodes: [LatLng(45.0, lng), LatLng(45.02, lng - 0.02)],
    distanceKm: 8,
    windingScore: 6,
    starRating: 4,
    sharpCurveCount: 8,
    centerPoint: LatLng(45.01, lng - 0.01),
    distanceFromUser: 5,
    tightCurveKm: 1,
    mediumCurveKm: 1,
    maxContinuousKm: 1,
    routeRankScore: 6,
    flowScore: 1,
  );
}

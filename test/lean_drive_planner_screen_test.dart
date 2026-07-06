import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:revv_app/core/app_language.dart';
import 'package:revv_app/models/drive_plan.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/screens/lean_drive_planner_screen.dart';
import 'package:revv_app/services/drive_planner_service.dart';
import 'package:revv_app/services/location_service.dart';
import 'package:revv_app/services/place_search_service.dart';
import 'package:revv_app/services/settings_service.dart';
import 'package:revv_app/services/weather_service.dart';
import 'package:revv_app/theme/text_styles.dart';
import 'package:revv_app/widgets/map_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const forbiddenWords = ['MAX', 'BEST', 'PEAK', '어택', '스릴', '경쟁'];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppText.forceSystemFonts = true;
  });

  Future<void> pumpPlanner(
    WidgetTester tester, {
    required DrivePlan plan,
    DrivePlan? lightPlan,
    DrivePlan? extendedPlan,
    TimeOfDay? arriveBy,
    PlaceSearchService? placeSearch,
  }) async {
    final location = LocationService()..hasPermission = true;
    final settings = SettingsService();
    await settings.setAppLanguage(AppLanguage.korean);
    await tester.binding.setSurfaceSize(const Size(430, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LocationService>.value(value: location),
          ChangeNotifierProvider<SettingsService>.value(value: settings),
          ChangeNotifierProvider(create: (_) => WeatherService()),
        ],
        child: MaterialApp(
          home: LeanDrivePlannerScreen(
            planner: _FakePlanner(
              plan,
              lightPlan: lightPlan,
              extendedPlan: extendedPlan,
            ),
            placeSearch: placeSearch,
            originResolver: (_) async => const LatLng(45.5, -73.6),
            initialArriveBy: arriveBy,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> selectMapPinDestination(WidgetTester tester) async {
    await tester.tap(find.text('어디로 갈까요?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('지도 핀으로 지정'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('이 지점으로'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
  }

  testWidgets('planner starts as one input sheet without a center pin', (
    tester,
  ) async {
    await pumpPlanner(tester, plan: _planWithWinding(windingMinutes: 30));

    expect(find.byType(DraggableScrollableSheet), findsOneWidget);
    expect(find.text('어디로 갈까요?'), findsOneWidget);
    expect(find.text('출발: 현위치 ▾'), findsOneWidget);
    expect(find.byIcon(Icons.location_pin), findsNothing);
  });

  testWidgets('planner moves from input to result state', (tester) async {
    await pumpPlanner(tester, plan: _planWithWinding(windingMinutes: 30));

    expect(find.text('여정 만들기'), findsNothing);
    expect(find.text('어디로 갈까요?'), findsOneWidget);

    await selectMapPinDestination(tester);

    expect(find.text('여정 타임라인'), findsNothing);
    expect(find.text('이동 10분'), findsOneWidget);
    expect(find.text('Lakeside Road 30분'), findsOneWidget);
    expect(
      find.textContaining(RegExp(r'도착 ~\d{2}:\d{2} · 45분 · 와인딩 30분')),
      findsOneWidget,
    );
    expect(find.text('드라이브 시작'), findsOneWidget);
    expect(find.textContaining(RegExp(r'\d+\.\d{4}')), findsNothing);
  });

  testWidgets('planner passes legible map mode and plan markers to MapWidget', (
    tester,
  ) async {
    await pumpPlanner(tester, plan: _planWithWinding(windingMinutes: 30));

    await selectMapPinDestination(tester);

    final map = tester.widget<MapWidget>(find.byType(MapWidget));
    expect(map.curveHeatmap, isFalse);
    final markers = map.planMarkers ?? const <PlanMapMarker>[];
    expect(
      markers.map((marker) => marker.kind),
      containsAll([
        PlanMapMarkerKind.origin,
        PlanMapMarkerKind.destination,
        PlanMapMarkerKind.windingStart,
      ]),
    );
  });

  testWidgets('timeline renders map color dots for transit and winding legs', (
    tester,
  ) async {
    await pumpPlanner(tester, plan: _planWithWinding(windingMinutes: 30));

    await selectMapPinDestination(tester);

    expect(find.byKey(const Key('timeline-dot-transit')), findsNWidgets(2));
    expect(find.byKey(const Key('timeline-dot-winding')), findsOneWidget);
  });

  testWidgets('planner map is not covered by a full-screen scroll overlay', (
    tester,
  ) async {
    await pumpPlanner(tester, plan: _planWithWinding(windingMinutes: 30));

    final fullScreenScrollOverlays = tester
        .widgetList<SafeArea>(find.byType(SafeArea))
        .where((safeArea) => safeArea.child is ListView);
    expect(fullScreenScrollOverlays, isEmpty);

    await selectMapPinDestination(tester);

    expect(find.byKey(const Key('planner-results-sheet')), findsOneWidget);
    final sheet = tester.widget<DraggableScrollableSheet>(
      find.byType(DraggableScrollableSheet),
    );
    expect(sheet.snap, isTrue);
    expect(sheet.snapSizes, const [0.18, 0.42, 0.85]);
    expect(sheet.minChildSize, 0.18);
    expect(sheet.initialChildSize, 0.42);
    expect(sheet.maxChildSize, 0.85);
  });

  testWidgets('planner shows the center pin only while picking a map point', (
    tester,
  ) async {
    await pumpPlanner(tester, plan: _planWithWinding(windingMinutes: 30));

    expect(find.byIcon(Icons.location_pin), findsNothing);

    await tester.tap(find.text('어디로 갈까요?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('지도 핀으로 지정'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.location_pin), findsOneWidget);
    expect(find.text('이 지점으로'), findsOneWidget);

    await tester.tap(find.text('이 지점으로'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.location_pin), findsNothing);
  });

  testWidgets('planner explains budget shortfall honestly', (tester) async {
    await pumpPlanner(tester, plan: _planWithWinding(windingMinutes: 12));

    await selectMapPinDestination(tester);

    expect(find.text('와인딩 12/30분'), findsOneWidget);
  });

  testWidgets('planner explains zero winding result and direct navigation', (
    tester,
  ) async {
    await pumpPlanner(tester, plan: _planWithoutWinding());

    await selectMapPinDestination(tester);

    expect(find.textContaining('이 경로엔 아직 발견된 와인딩이 없어요'), findsOneWidget);
    expect(find.text('드라이브 시작'), findsOneWidget);
    final startButton = tester.widget<ElevatedButton>(
      find.ancestor(
        of: find.text('드라이브 시작'),
        matching: find.byType(ElevatedButton),
      ),
    );
    expect(startButton.onPressed, isNull);
  });

  testWidgets('planner labels approximate transit geometry', (tester) async {
    await pumpPlanner(
      tester,
      plan: _planWithWinding(windingMinutes: 30, usesApproximateTransit: true),
    );

    await selectMapPinDestination(tester);

    expect(find.textContaining('대략 경로'), findsOneWidget);
  });

  test('Google Maps app URL includes planner waypoints', () {
    final uri = buildGoogleMapsAppUri(
      origin: const LatLng(45.5, -73.6),
      destination: const LatLng(45.7, -73.8),
      waypoints: const [LatLng(45.55, -73.65), LatLng(45.6, -73.7)],
    );

    expect(uri.scheme, 'comgooglemapsurl');
    expect(uri.host, 'www.google.com');
    expect(uri.path, '/maps/dir/');
    expect(uri.queryParameters['api'], '1');
    expect(uri.queryParameters['saddr'], '45.5000,-73.6000');
    expect(uri.queryParameters['daddr'], '45.7000,-73.8000');
    expect(
      uri.queryParameters['waypoints'],
      '45.5500,-73.6500|45.6000,-73.7000',
    );
  });

  test('buildPlanMapMarkers creates start and end markers for each winding leg', () {
    const firstStart = LatLng(45.1, -73.1);
    const firstEnd = LatLng(45.2, -73.2);
    const secondStart = LatLng(45.3, -73.3);
    const secondEnd = LatLng(45.4, -73.4);
    const plan = DrivePlan(
      legs: [
        DrivePlanLeg(
          kind: DrivePlanLegKind.winding,
          nodes: [firstStart, firstEnd],
          distanceKm: 8,
          estimatedMinutes: 12,
        ),
        DrivePlanLeg(
          kind: DrivePlanLegKind.winding,
          nodes: [secondStart, secondEnd],
          distanceKm: 7,
          estimatedMinutes: 10,
        ),
      ],
      totalMinutes: 22,
      windingMinutes: 22,
      transitMinutes: 0,
      waypoints: [firstStart, firstEnd, secondStart, secondEnd],
    );

    final markers = buildPlanMapMarkers(
      origin: const LatLng(45.0, -73.0),
      destination: const LatLng(45.5, -73.5),
      plan: plan,
    );

    expect(markers.map((marker) => marker.kind), [
      PlanMapMarkerKind.origin,
      PlanMapMarkerKind.destination,
      PlanMapMarkerKind.windingStart,
      PlanMapMarkerKind.windingEnd,
      PlanMapMarkerKind.windingStart,
      PlanMapMarkerKind.windingEnd,
    ]);
    expect(markers[2].point, firstStart);
    expect(markers[3].point, firstEnd);
    expect(markers[4].point, secondStart);
    expect(markers[5].point, secondEnd);
  });

  testWidgets('plan options switch the displayed timeline', (tester) async {
    await pumpPlanner(
      tester,
      plan: _planWithWinding(windingMinutes: 30),
      lightPlan: _planWithWinding(windingMinutes: 10, routeName: 'Hill Loop'),
    );

    await selectMapPinDestination(tester);

    // 기본 옵션이 먼저 표시된다
    expect(find.text('Lakeside Road 30분'), findsOneWidget);

    await tester.tap(find.textContaining('가볍게'));
    await tester.pumpAndSettle();

    expect(find.text('Hill Loop 10분'), findsOneWidget);
    expect(find.text('Lakeside Road 30분'), findsNothing);
  });

  testWidgets('rest legs render in the timeline', (tester) async {
    await pumpPlanner(tester, plan: _planWithRest());

    await selectMapPinDestination(tester);

    expect(find.text('휴식 15분'), findsOneWidget);
  });

  testWidgets('arrival time picks the longest fitting option', (tester) async {
    // 현재 시각 + 12시간: 오늘 또는 내일로 해석돼도 항상 12시간 이상 여유
    final now = TimeOfDay.now();
    final arriveBy = TimeOfDay(hour: (now.hour + 12) % 24, minute: now.minute);
    await pumpPlanner(
      tester,
      plan: _planWithWinding(windingMinutes: 30),
      lightPlan: _planWithWinding(windingMinutes: 10, routeName: 'Hill Loop'),
      extendedPlan: _planWithWinding(
        windingMinutes: 45,
        routeName: 'Ridge Sweep',
      ),
      arriveBy: arriveBy,
    );

    await selectMapPinDestination(tester);

    // 여유 충분 → 와인딩이 가장 긴 옵션이 추천되고 자동 선택된다
    expect(find.textContaining('추천'), findsOneWidget);
    expect(find.text('Ridge Sweep 45분'), findsOneWidget);
    expect(
      find.textContaining(RegExp(r'도착 ~\d{2}:\d{2} · 60분 · 와인딩 45분')),
      findsOneWidget,
    );
  });

  testWidgets('destination search updates the planner destination', (
    tester,
  ) async {
    final search = _FakePlaceSearch([
      const PlaceResult(
        name: 'Circuit Gilles-Villeneuve',
        address: 'Montreal, Quebec',
        point: LatLng(45.5001, -73.5229),
      ),
    ]);
    await pumpPlanner(
      tester,
      plan: _planWithWinding(windingMinutes: 30),
      placeSearch: search,
    );

    await tester.tap(find.text('어디로 갈까요?'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('planner-place-search-field')),
      'circuit',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(search.lastQuery, 'circuit');
    expect(search.lastLanguage, 'ko');
    expect(find.text('Circuit Gilles-Villeneuve'), findsOneWidget);

    await tester.tap(find.text('Circuit Gilles-Villeneuve'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(find.text('Circuit Gilles-Villeneuve'), findsOneWidget);
    expect(find.text('45.5017,-73.5673'), findsNothing);
    expect(find.textContaining(RegExp(r'\d+\.\d{4}')), findsNothing);
  });

  testWidgets('planner visible copy avoids forbidden terms', (tester) async {
    await pumpPlanner(tester, plan: _planWithWinding(windingMinutes: 12));

    await selectMapPinDestination(tester);

    final copy = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data)
        .whereType<String>();
    for (final value in copy) {
      for (final forbidden in forbiddenWords) {
        expect(value, isNot(contains(forbidden)));
      }
    }
  });
}

class _FakePlaceSearch extends PlaceSearchService {
  final List<PlaceResult> results;
  String? lastQuery;
  String? lastLanguage;

  _FakePlaceSearch(this.results);

  @override
  bool get isEnabled => true;

  @override
  Future<List<PlaceResult>> searchPlaces(
    String query, {
    LatLng? proximity,
    String language = 'en',
  }) async {
    lastQuery = query;
    lastLanguage = language;
    return results;
  }
}

class _FakePlanner extends DrivePlannerService {
  final DrivePlan plan;
  final DrivePlan? lightPlan;
  final DrivePlan? extendedPlan;

  _FakePlanner(this.plan, {this.lightPlan, this.extendedPlan})
    : super(
        candidateLoader: (_, _) async => const [],
        transitLegLoader: (_) async => const [],
      );

  @override
  Future<DrivePlan?> buildPlan(DrivePlanRequest request) async {
    return plan;
  }

  @override
  Future<List<DrivePlanOption>> buildPlanOptions(
    DrivePlanRequest request,
  ) async {
    return [
      DrivePlanOption(
        kind: DrivePlanOptionKind.light,
        budgetMinutes: (request.windingBudgetMinutes * 0.6).round(),
        plan: lightPlan ?? plan,
      ),
      DrivePlanOption(
        kind: DrivePlanOptionKind.standard,
        budgetMinutes: request.windingBudgetMinutes,
        plan: plan,
      ),
      DrivePlanOption(
        kind: DrivePlanOptionKind.extended,
        budgetMinutes: (request.windingBudgetMinutes * 1.5).round(),
        plan: extendedPlan ?? plan,
      ),
    ];
  }
}

DrivePlan _planWithRest() {
  final base = _planWithWinding(windingMinutes: 30);
  return DrivePlan(
    legs: [
      ...base.legs,
      const DrivePlanLeg(
        kind: DrivePlanLegKind.rest,
        nodes: [],
        distanceKm: 0,
        estimatedMinutes: 15,
      ),
      const DrivePlanLeg(
        kind: DrivePlanLegKind.transit,
        nodes: [LatLng(45.7, -73.8), LatLng(45.75, -73.85)],
        distanceKm: 5,
        estimatedMinutes: 8,
      ),
    ],
    totalMinutes: base.totalMinutes + 23,
    windingMinutes: base.windingMinutes,
    transitMinutes: base.transitMinutes + 8,
    restMinutes: 15,
    waypoints: base.waypoints,
    budgetShortfallMinutes: 0,
  );
}

DrivePlan _planWithWinding({
  required int windingMinutes,
  String routeName = 'Lakeside Road',
  bool usesApproximateTransit = false,
}) {
  final route = RevvRoute(
    id: 'lakeside',
    name: routeName,
    nodes: const [LatLng(45.55, -73.65), LatLng(45.60, -73.70)],
    distanceKm: 12,
    windingScore: 5,
    starRating: 4,
    sharpCurveCount: 8,
    centerPoint: const LatLng(45.57, -73.67),
    distanceFromUser: 3,
  );
  return DrivePlan(
    legs: [
      const DrivePlanLeg(
        kind: DrivePlanLegKind.transit,
        nodes: [LatLng(45.5, -73.6), LatLng(45.55, -73.65)],
        distanceKm: 8,
        estimatedMinutes: 10,
      ),
      DrivePlanLeg(
        kind: DrivePlanLegKind.winding,
        nodes: route.nodes,
        distanceKm: route.distanceKm,
        estimatedMinutes: windingMinutes,
        route: route,
      ),
      const DrivePlanLeg(
        kind: DrivePlanLegKind.transit,
        nodes: [LatLng(45.60, -73.70), LatLng(45.7, -73.8)],
        distanceKm: 6,
        estimatedMinutes: 5,
      ),
    ],
    totalMinutes: windingMinutes + 15,
    windingMinutes: windingMinutes,
    transitMinutes: 15,
    waypoints: const [
      LatLng(45.5, -73.6),
      LatLng(45.55, -73.65),
      LatLng(45.60, -73.70),
      LatLng(45.7, -73.8),
    ],
    budgetShortfallMinutes: 30 - windingMinutes,
    usesApproximateTransit: usesApproximateTransit,
  );
}

DrivePlan _planWithoutWinding() {
  return const DrivePlan(
    legs: [
      DrivePlanLeg(
        kind: DrivePlanLegKind.transit,
        nodes: [LatLng(45.5, -73.6), LatLng(45.7, -73.8)],
        distanceKm: 20,
        estimatedMinutes: 24,
      ),
    ],
    totalMinutes: 24,
    windingMinutes: 0,
    transitMinutes: 24,
    waypoints: [LatLng(45.5, -73.6), LatLng(45.7, -73.8)],
    budgetShortfallMinutes: 30,
  );
}

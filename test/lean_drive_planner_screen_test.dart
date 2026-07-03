import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:revv_app/core/app_language.dart';
import 'package:revv_app/models/drive_plan.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/screens/lean_drive_planner_screen.dart';
import 'package:revv_app/services/drive_planner_service.dart';
import 'package:revv_app/services/location_service.dart';
import 'package:revv_app/services/settings_service.dart';
import 'package:revv_app/services/weather_service.dart';
import 'package:revv_app/theme/text_styles.dart';
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
            planner: _FakePlanner(plan),
            originResolver: (_) async => const LatLng(45.5, -73.6),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('planner moves from input to result state', (tester) async {
    await pumpPlanner(tester, plan: _planWithWinding(windingMinutes: 30));

    expect(find.text('여정 만들기'), findsOneWidget);

    await tester.tap(find.text('여정 만들기'));
    await tester.pumpAndSettle();

    expect(find.text('여정 타임라인'), findsOneWidget);
    expect(find.text('이동 10분'), findsOneWidget);
    expect(find.text('Lakeside Road 30분'), findsOneWidget);
    expect(find.text('총 45분 · 와인딩 67%'), findsOneWidget);
  });

  testWidgets('planner explains budget shortfall honestly', (tester) async {
    await pumpPlanner(tester, plan: _planWithWinding(windingMinutes: 12));

    await tester.tap(find.text('여정 만들기'));
    await tester.pumpAndSettle();

    expect(find.text('와인딩 12분을 채웠어요 (목표 30분)'), findsOneWidget);
  });

  testWidgets('planner explains zero winding result and direct navigation', (
    tester,
  ) async {
    await pumpPlanner(tester, plan: _planWithoutWinding());

    await tester.tap(find.text('여정 만들기'));
    await tester.pumpAndSettle();

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

  testWidgets('planner visible copy avoids forbidden terms', (tester) async {
    await pumpPlanner(tester, plan: _planWithWinding(windingMinutes: 12));

    await tester.tap(find.text('여정 만들기'));
    await tester.pumpAndSettle();

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

class _FakePlanner extends DrivePlannerService {
  final DrivePlan plan;

  _FakePlanner(this.plan)
    : super(
        candidateLoader: (_, _) async => const [],
        transitLegLoader: (_) async => const [],
      );

  @override
  Future<DrivePlan?> buildPlan(DrivePlanRequest request) async {
    return plan;
  }
}

DrivePlan _planWithWinding({required int windingMinutes}) {
  final route = RevvRoute(
    id: 'lakeside',
    name: 'Lakeside Road',
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

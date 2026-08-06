import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:revv_app/core/app_language.dart';
import 'package:revv_app/models/drive_plan.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/screens/lean_drive_screen.dart';
import 'package:revv_app/services/drive_plan_navigation.dart';
import 'package:revv_app/services/imu_service.dart';
import 'package:revv_app/services/location_service.dart';
import 'package:revv_app/services/route_turn_service.dart';
import 'package:revv_app/services/run_session_service.dart';
import 'package:revv_app/services/settings_service.dart';
import 'package:revv_app/services/voice_briefing_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('chain drive loads every leg and renders chain progress', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService();
    await settings.setAppLanguage(AppLanguage.korean);
    final session = RunSessionService();
    final imu = ImuService();
    addTearDown(imu.dispose);
    final turns = _RecordingTurnService();
    final route = buildDrivePlanRoute(
      plan: _plan,
      windingRoutes: const [_first, _second],
      name: '루트 체인 · 2개',
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(value: settings),
          ChangeNotifierProvider<RunSessionService>.value(value: session),
          ChangeNotifierProvider<ImuService>.value(value: imu),
          ChangeNotifierProvider(create: (_) => LocationService()),
        ],
        child: MaterialApp(
          home: LeanDriveScreen(
            route: route,
            drivePlan: _plan,
            simulated: true,
            routeTurnService: turns,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 800));

    expect(turns.calls, 1);
    expect(turns.lastLegs, hasLength(4));
    expect(find.text('루트 체인 · 2개'), findsOneWidget);
    expect(find.text('체인 1/2'), findsOneWidget);
    expect(find.text('우측'), findsOneWidget);
    expect(find.text('흐름 구간'), findsNothing);
    expect(find.text('위치 권한이 필요해요'), findsNothing);
    expect(session.isRecording, isTrue);
    expect(session.currentRoute?.id, 'chain:first/second');
  });

  testWidgets('simulated drive passes route elevation into voice guidance', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService();
    await settings.setAppLanguage(AppLanguage.english);
    final session = RunSessionService();
    final imu = ImuService();
    final spoken = <String>[];
    addTearDown(imu.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(value: settings),
          ChangeNotifierProvider<RunSessionService>.value(value: session),
          ChangeNotifierProvider<ImuService>.value(value: imu),
          ChangeNotifierProvider(create: (_) => LocationService()),
        ],
        child: MaterialApp(
          home: LeanDriveScreen(
            route: _elevationRoute,
            simulated: true,
            routeTurnService: _NoTurnService(),
            voiceOverride: VoiceBriefingService(
              speak: (text, _) async => spoken.add(text),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(spoken, ['climb, 50 meters']);
  });

  testWidgets('route-wide aggregates never become positional voice calls', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService();
    await settings.setAppLanguage(AppLanguage.english);
    final session = RunSessionService();
    final imu = ImuService();
    final spoken = <String>[];
    addTearDown(imu.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(value: settings),
          ChangeNotifierProvider<RunSessionService>.value(value: session),
          ChangeNotifierProvider<ImuService>.value(value: imu),
          ChangeNotifierProvider(create: (_) => LocationService()),
        ],
        child: MaterialApp(
          home: LeanDriveScreen(
            route: _aggregateOnlyRoute,
            simulated: true,
            routeTurnService: _NoTurnService(),
            voiceOverride: VoiceBriefingService(
              speak: (text, _) async => spoken.add(text),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(spoken, isEmpty);
  });
}

class _RecordingTurnService extends RouteTurnService {
  int calls = 0;
  List<List<LatLng>> lastLegs = const [];

  @override
  Future<List<NavStep>> fetchStepsForLegs(List<List<LatLng>> routeLegs) async {
    calls++;
    lastLegs = routeLegs;
    return const [
      NavStep(
        sequence: 1,
        maneuverType: 'turn',
        modifier: 'right',
        location: LatLng(45.003, -73),
        distanceFromStartM: 300,
        segmentDistanceM: 500,
      ),
    ];
  }
}

class _NoTurnService extends RouteTurnService {
  @override
  Future<List<NavStep>> fetchSteps(List<LatLng> routeNodes) async => const [];
}

const _elevationRoute = RevvRoute(
  id: 'elevation',
  name: 'Elevation route',
  nodes: [LatLng(45, -73), LatLng(45.0045, -73), LatLng(45.009, -73)],
  distanceKm: 1,
  windingScore: 2,
  starRating: 2,
  sharpCurveCount: 0,
  elevationProfile: [100, 145, 145],
  centerPoint: LatLng(45.0045, -73),
  distanceFromUser: 0,
);

const _aggregateOnlyRoute = RevvRoute(
  id: 'aggregate-only',
  name: 'Aggregate route',
  nodes: [LatLng(45, -73), LatLng(45.0045, -73), LatLng(45.009, -73)],
  distanceKm: 1,
  windingScore: 2,
  starRating: 2,
  sharpCurveCount: 8,
  stopSignCount: 5,
  trafficSignalCount: 2,
  isBridgeLike: true,
  surfaceSummary: 'gravel',
  speedLimitSummary: '50',
  cautionNote: 'route-wide only',
  centerPoint: LatLng(45.0045, -73),
  distanceFromUser: 0,
);

const _first = RevvRoute(
  id: 'first',
  name: 'First',
  nodes: [LatLng(45.01, -73), LatLng(45.02, -73)],
  distanceKm: 2,
  windingScore: 6,
  starRating: 4,
  sharpCurveCount: 2,
  centerPoint: LatLng(45.015, -73),
  distanceFromUser: 0,
);

const _second = RevvRoute(
  id: 'second',
  name: 'Second',
  nodes: [LatLng(45.03, -73), LatLng(45.04, -73)],
  distanceKm: 2,
  windingScore: 7,
  starRating: 4,
  sharpCurveCount: 3,
  centerPoint: LatLng(45.035, -73),
  distanceFromUser: 0,
);

const _plan = DrivePlan(
  legs: [
    DrivePlanLeg(
      kind: DrivePlanLegKind.transit,
      nodes: [
        LatLng(45, -73),
        LatLng(45.001, -73),
        LatLng(45.005, -73),
        LatLng(45.01, -73),
      ],
      distanceKm: 1,
      estimatedMinutes: 2,
    ),
    DrivePlanLeg(
      kind: DrivePlanLegKind.winding,
      nodes: [LatLng(45.01, -73), LatLng(45.02, -73)],
      distanceKm: 2,
      estimatedMinutes: 3,
      route: _first,
    ),
    DrivePlanLeg(
      kind: DrivePlanLegKind.transit,
      nodes: [LatLng(45.02, -73), LatLng(45.03, -73)],
      distanceKm: 1,
      estimatedMinutes: 2,
    ),
    DrivePlanLeg(
      kind: DrivePlanLegKind.winding,
      nodes: [LatLng(45.03, -73), LatLng(45.04, -73)],
      distanceKm: 2,
      estimatedMinutes: 3,
      route: _second,
    ),
  ],
  totalMinutes: 10,
  windingMinutes: 6,
  transitMinutes: 4,
  waypoints: [
    LatLng(45, -73),
    LatLng(45.01, -73),
    LatLng(45.02, -73),
    LatLng(45.03, -73),
    LatLng(45.04, -73),
  ],
);

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:revv_app/core/app_language.dart';
import 'package:revv_app/core/storage_keys.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/services/route_service.dart';
import 'package:revv_app/services/settings_service.dart';
import 'package:revv_app/ui/copilot_briefing.dart';
import 'package:revv_app/widgets/copilot_start_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Google Maps handoff navigates to the route start', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService();
    await settings.setAppLanguage(AppLanguage.korean);
    final launched = <Uri>[];

    await _pumpSheet(
      tester,
      route: _routeWithNodes(14),
      settings: settings,
      launcher: (uri, {required mode}) async {
        launched.add(uri);
        return true;
      },
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Google Maps'));
    await tester.pumpAndSettle();

    final uri = launched.single;
    expect(uri.scheme, 'comgooglemapsurl');
    expect(uri.queryParameters['origin'], isNull);
    expect(uri.queryParameters['destination'], '45.00000,-73.00000');
    expect(uri.queryParameters['waypoints'], isNull);
    expect(uri.queryParameters['travelmode'], 'driving');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(StorageKeys.pendingDriveRouteId), 'route');
    expect(prefs.getString(StorageKeys.pendingDriveSavedAt), isNotNull);
  });

  testWidgets('Waze button labels start-only handoff', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService();
    await settings.setAppLanguage(AppLanguage.korean);

    final launched = <Uri>[];
    await _pumpSheet(
      tester,
      route: _routeWithNodes(4),
      settings: settings,
      launcher: (uri, {required mode}) async {
        launched.add(uri);
        return true;
      },
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Waze'), findsOneWidget);
    expect(find.text('시작점까지'), findsOneWidget);

    await tester.tap(find.text('Waze'));
    await tester.pumpAndSettle();

    expect(launched.single.scheme, 'https');
    expect(launched.single.host, 'waze.com');
  });

  testWidgets('far route shows briefing before test drive action', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService();
    await settings.setAppLanguage(AppLanguage.english);
    final route = _routeWithNodes(4);
    final briefing = CopilotRouteBriefing.fromRoute(
      route,
      startDistanceKm: route.distanceFromUser,
      language: AppLanguage.english,
    );

    await _pumpSheet(
      tester,
      route: route,
      settings: settings,
      launcher: (_, {required mode}) async => true,
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Google Maps'), findsOneWidget);
    expect(find.text('Start here'), findsOneWidget);
    expect(find.text(briefing.startAdvice), findsOneWidget);
    expect(find.text(briefing.primaryAdvice), findsOneWidget);
    expect(find.text(briefing.riskAdvice), findsOneWidget);
    expect(find.text('Test drive from here'), findsOneWidget);

    final labels = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data)
        .whereType<String>()
        .toList();
    expect(
      labels.indexOf(briefing.primaryAdvice),
      lessThan(labels.indexOf('Test drive from here')),
    );
    expect(
      labels.indexOf(briefing.riskAdvice),
      lessThan(labels.indexOf('Test drive from here')),
    );
  });

  testWidgets('near route shows route-wide safety context before starting', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService();
    await settings.setAppLanguage(AppLanguage.english);
    final route = _routeWithNodes(4).copyWith(
      distanceFromUser: 0.2,
      stopSignCount: 5,
      trafficSignalCount: 2,
      surfaceSummary: 'asphalt',
      speedLimitSummary: '80',
    );
    final briefing = CopilotRouteBriefing.fromRoute(
      route,
      language: AppLanguage.english,
    );

    await _pumpSheet(
      tester,
      route: route,
      settings: settings,
      launcher: (_, {required mode}) async => true,
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text(briefing.riskAdvice), findsOneWidget);
    expect(find.text(briefing.routeContextAdvice), findsOneWidget);
    expect(briefing.riskAdvice, contains('7 stops'));
    expect(
      briefing.routeContextAdvice,
      'Route-wide · 5 stop signs · 2 signals · surface asphalt · limit data 80',
    );
  });

  testWidgets('Google Maps reports failure when app and web handoffs throw', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService();
    await settings.setAppLanguage(AppLanguage.korean);
    final launched = <Uri>[];

    await _pumpSheet(
      tester,
      route: _routeWithNodes(4),
      settings: settings,
      launcher: (uri, {required mode}) async {
        launched.add(uri);
        throw Exception('launcher unavailable');
      },
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Google Maps'));
    await tester.pumpAndSettle();

    expect(launched, hasLength(2));
    expect(launched.first.scheme, 'comgooglemapsurl');
    expect(launched.last.scheme, 'https');
    expect(find.text('Google Maps'), findsOneWidget);
  });

  testWidgets('arrived prompt uses resume copy', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService();
    await settings.setAppLanguage(AppLanguage.korean);

    await _pumpSheet(
      tester,
      route: _routeWithNodes(4).copyWith(distanceFromUser: 0.2),
      settings: settings,
      arrivedPrompt: true,
      launcher: (_, {required mode}) async => true,
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('루트 도착! 주행 시작할까요?'), findsOneWidget);
  });
}

Future<void> _pumpSheet(
  WidgetTester tester, {
  required RevvRoute route,
  required SettingsService settings,
  required NavigationUrlLauncher launcher,
  bool arrivedPrompt = false,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsService>.value(value: settings),
        ChangeNotifierProvider<RouteService>.value(value: RouteService()),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showCopilotStartSheet(
                context,
                route: route,
                launchNavigationUrl: launcher,
                arrivedPrompt: arrivedPrompt,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
}

RevvRoute _routeWithNodes(int count) {
  final nodes = List.generate(
    count,
    (index) => LatLng(45 + index * 0.01, -73 - index * 0.01),
  );
  return RevvRoute(
    id: 'route',
    name: 'Route',
    nodes: nodes,
    distanceKm: 12,
    windingScore: 6,
    starRating: 4,
    sharpCurveCount: 8,
    centerPoint: const LatLng(45.06, -73.06),
    distanceFromUser: 5,
  );
}

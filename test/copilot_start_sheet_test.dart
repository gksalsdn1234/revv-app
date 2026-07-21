import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:revv_app/core/app_language.dart';
import 'package:revv_app/core/storage_keys.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/services/route_service.dart';
import 'package:revv_app/services/settings_service.dart';
import 'package:revv_app/widgets/copilot_start_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Google Maps handoff includes route end and reduced waypoints', (
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
    expect(uri.queryParameters['origin'], '45.00000,-73.00000');
    expect(uri.queryParameters['destination'], '45.13000,-73.13000');
    expect(uri.queryParameters['travelmode'], 'driving');
    final waypoints = uri.queryParameters['waypoints']!.split('|');
    expect(waypoints, hasLength(lessThanOrEqualTo(2)));
    expect(waypoints.first, isNot('45.00000,-73.00000'));
    expect(waypoints.last, isNot('45.13000,-73.13000'));
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

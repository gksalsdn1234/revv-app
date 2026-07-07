import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:revv_app/core/app_language.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/services/route_service.dart';
import 'package:revv_app/services/settings_service.dart';
import 'package:revv_app/widgets/copilot_start_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Google Maps handoff includes route end and sampled waypoints', (
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
    expect(uri.queryParameters['saddr'], '45.0000,-73.0000');
    expect(uri.queryParameters['daddr'], '45.1300,-73.1300');
    final waypoints = uri.queryParameters['waypoints']!.split('|');
    expect(waypoints, hasLength(9));
    expect(waypoints.first, isNot('45.0000,-73.0000'));
    expect(waypoints.last, isNot('45.1300,-73.1300'));
  });

  testWidgets('Waze button labels start-only handoff', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService();
    await settings.setAppLanguage(AppLanguage.korean);

    await _pumpSheet(
      tester,
      route: _routeWithNodes(4),
      settings: settings,
      launcher: (_, {required mode}) async => true,
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Waze'), findsOneWidget);
    expect(find.text('시작점까지'), findsOneWidget);
  });
}

Future<void> _pumpSheet(
  WidgetTester tester, {
  required RevvRoute route,
  required SettingsService settings,
  required NavigationUrlLauncher launcher,
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

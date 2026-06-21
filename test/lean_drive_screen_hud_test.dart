import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:revv_app/core/app_language.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/screens/lean_drive_screen.dart';
import 'package:revv_app/services/location_service.dart';
import 'package:revv_app/services/run_session_service.dart';
import 'package:revv_app/services/settings_service.dart';
import 'package:revv_app/services/weather_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _technicalRouteNodes = [
  LatLng(45.0000, -73.0000),
  LatLng(45.0010, -73.0000),
  LatLng(45.0010, -72.9985),
  LatLng(45.0024, -72.9985),
  LatLng(45.0024, -72.9970),
];

void main() {
  testWidgets('LeanDriveScreen renders route corner metadata in the HUD', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService();
    await settings.setAppLanguage(AppLanguage.korean);

    const route = RevvRoute(
      id: 'technical-route',
      name: '테크니컬 루트',
      nodes: _technicalRouteNodes,
      distanceKm: 0.5,
      windingScore: 8.2,
      starRating: 5,
      sharpCurveCount: 3,
      centerPoint: LatLng(45.0012, -72.9990),
      distanceFromUser: 0,
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(value: settings),
          ChangeNotifierProvider<RunSessionService>(
            create: (_) => RunSessionService(),
          ),
          ChangeNotifierProvider<LocationService>(
            create: (_) => LocationService(),
          ),
          ChangeNotifierProvider<WeatherService>(
            create: (_) => WeatherService(),
          ),
        ],
        child: const MaterialApp(
          home: LeanDriveScreen(route: route, simulated: true),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('준비'), findsOneWidget);
    expect(find.text('시케인'), findsOneWidget);
    expect(find.textContaining('짧은 전환'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text && RegExp(r'^\d+초$').hasMatch(widget.data ?? ''),
      ),
      findsOneWidget,
    );
  });
}

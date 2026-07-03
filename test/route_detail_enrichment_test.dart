import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/screens/lean_route_detail_screen.dart';
import 'package:revv_app/services/settings_service.dart';

RevvRoute _route({
  List<double>? elevationProfile,
  double elevationDelta = 0,
  double tightCurveKm = 0,
  double mediumCurveKm = 0,
  double maxContinuousKm = 0,
  int sharpCurveCount = 0,
  List<String> roadNames = const [],
  String surfaceSummary = '',
  String speedLimitSummary = '',
  List<String> nearbyPoiNames = const [],
  int runCount = 0,
  bool isLoop = false,
}) {
  return RevvRoute(
    id: 'detail-route',
    name: 'Detail Route',
    nodes: const [
      LatLng(45.0000, -73.0000),
      LatLng(45.0100, -72.9900),
      LatLng(45.0200, -73.0050),
    ],
    distanceKm: 12,
    windingScore: 6.2,
    starRating: 4,
    sharpCurveCount: sharpCurveCount,
    elevationDelta: elevationDelta,
    centerPoint: const LatLng(45.0100, -73.0000),
    distanceFromUser: 2.5,
    tightCurveKm: tightCurveKm,
    mediumCurveKm: mediumCurveKm,
    maxContinuousKm: maxContinuousKm,
    isLoop: isLoop,
    roadNames: roadNames,
    surfaceSummary: surfaceSummary,
    speedLimitSummary: speedLimitSummary,
    nearbyPoiNames: nearbyPoiNames,
    elevationProfile: elevationProfile,
    runCount: runCount,
  );
}

Future<void> _pumpRoute(WidgetTester tester, RevvRoute route) async {
  await tester.binding.setSurfaceSize(const Size(390, 2200));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ChangeNotifierProvider<SettingsService>.value(
      value: SettingsService(),
      child: MaterialApp(home: LeanRouteDetailScreen(route: route)),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectNoForbiddenSafetyWords(String text) {
  expect(
    text,
    isNot(
      matches(
        RegExp(
          r'\b(MAX|BEST|PEAK|RECORD)\b|Attack|어택|최고|최대|신기록',
          caseSensitive: false,
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('route detail renders enrichment sections when data exists', (
    tester,
  ) async {
    final route = _route(
      elevationProfile: const [120, 145, 132, 178],
      tightCurveKm: 1.4,
      mediumCurveKm: 2.1,
      maxContinuousKm: 1.8,
      sharpCurveCount: 7,
      roadNames: const ['Chemin du Lac', 'North Ridge', 'Route 329', 'Rue Sud'],
      surfaceSummary: 'asphalt',
      speedLimitSummary: '50',
      nearbyPoiNames: const ['Cafe Nord', 'Belvedere Est', 'Lookout'],
      runCount: 5,
      isLoop: true,
    );

    await _pumpRoute(tester, route);

    expect(find.text('ELEVATION PROFILE'), findsOneWidget);
    expect(find.text('Delta 58m'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.text('CURVE MIX'), findsOneWidget);
    expect(
      find.text('Tight 1.4km · Medium 2.1km · Sharp curves 7'),
      findsOneWidget,
    );
    expect(find.text('Longest winding flow 1.8km'), findsOneWidget);
    expect(find.text('ROAD INFO'), findsOneWidget);
    expect(
      find.text('Chemin du Lac → North Ridge → Route 329 → Rue Sud'),
      findsOneWidget,
    );
    expect(find.text('Surface asphalt'), findsOneWidget);
    expect(
      find.text('Posted speed-limit sections 50 — follow roadside signs'),
      findsOneWidget,
    );
    expect(find.text('JOURNEY INFO'), findsOneWidget);
    expect(
      find.text('Nearby: Cafe Nord · Belvedere Est · Lookout'),
      findsOneWidget,
    );
    expect(find.text('REVV runs 5'), findsOneWidget);
    expect(find.text('LOOP'), findsOneWidget);
    expect(find.text('Flow'), findsNothing);

    _expectNoForbiddenSafetyWords(
      [
        'Delta 58m',
        'Tight 1.4km · Medium 2.1km · Sharp curves 7',
        'Longest winding flow 1.8km',
        'Posted speed-limit sections 50 — follow roadside signs',
        'Nearby: Cafe Nord · Belvedere Est · Lookout',
        'REVV runs 5',
        'LOOP',
      ].join(' | '),
    );
  });

  testWidgets('route detail hides enrichment sections when data is empty', (
    tester,
  ) async {
    await _pumpRoute(tester, _route());

    expect(find.text('ELEVATION PROFILE'), findsNothing);
    expect(find.text('CURVE MIX'), findsNothing);
    expect(find.text('ROAD INFO'), findsNothing);
    expect(find.text('JOURNEY INFO'), findsNothing);
    expect(find.text('Flow'), findsOneWidget);
  });
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/screens/lean_route_finder_screen.dart';
import 'package:revv_app/services/driven_routes_service.dart';
import 'package:revv_app/services/location_service.dart';
import 'package:revv_app/services/route_service.dart';
import 'package:revv_app/services/run_history_service.dart';
import 'package:revv_app/services/settings_service.dart';
import 'package:revv_app/services/supabase_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:revv_app/services/place_search_service.dart';
import 'package:revv_app/widgets/place_search_sheet.dart';
import 'package:revv_app/widgets/map_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'cancelling place search preserves the initial location request',
    (tester) async {
      await _surface(tester);
      final permission = Completer<void>()..complete();
      final fix = Completer<LatLng?>();
      final location = _DelayedLocation(permission, fix);
      final routes = _QuietRoutes();
      final history = RunHistoryService();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => SettingsService()),
            ChangeNotifierProvider<LocationService>.value(value: location),
            ChangeNotifierProvider<RouteService>.value(value: routes),
            ChangeNotifierProvider(
              create: (_) => DrivenRoutesService(history: history),
            ),
            ChangeNotifierProvider.value(value: SupabaseService()),
          ],
          child: MaterialApp(
            home: LeanRouteFinderScreen(placeSearch: _MontrealSearch()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Search an area'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(PlaceSearchSheet),
          matching: find.byIcon(Icons.close_rounded),
        ),
      );
      await tester.pumpAndSettle();
      fix.complete(const LatLng(37.5665, 126.978));
      await tester.pumpAndSettle();
      expect(routes.fetches, 1);
      expect(routes.points.single.lat, 37.5665);
    },
  );

  testWidgets('explicit area selection ignores the late initial GPS result', (
    tester,
  ) async {
    await _surface(tester);
    final permission = Completer<void>()..complete();
    final fix = Completer<LatLng?>();
    final location = _DelayedLocation(permission, fix);
    final routes = _QuietRoutes();
    final history = RunHistoryService();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsService()),
          ChangeNotifierProvider<LocationService>.value(value: location),
          ChangeNotifierProvider<RouteService>.value(value: routes),
          ChangeNotifierProvider(
            create: (_) => DrivenRoutesService(history: history),
          ),
          ChangeNotifierProvider.value(value: SupabaseService()),
        ],
        child: MaterialApp(
          home: LeanRouteFinderScreen(placeSearch: _MontrealSearch()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Search an area'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(plannerPlaceSearchFieldKey), 'Montreal');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Montreal').last);
    await tester.pumpAndSettle();
    expect(
      tester.widget<MapWidget>(find.byType(MapWidget)).cameraTarget?.lat,
      45.5017,
    );
    fix.complete(const LatLng(37.5665, 126.978));
    await tester.pumpAndSettle();
    expect(
      tester.widget<MapWidget>(find.byType(MapWidget)).cameraTarget?.lat,
      45.5017,
    );
    expect(routes.points.last.lat, 45.5017);
    expect(routes.fetches, 1);
  });
  testWidgets('first field frames all nearby routes', (tester) async {
    await _surface(tester);
    final location = _DelayedLocation(
      Completer<void>()..complete(),
      Completer<LatLng?>()..complete(const LatLng(45.5017, -73.5673)),
    );
    final routes = _QuietRoutes()
      ..results = [
        for (var i = 0; i < 8; i++)
          RevvRoute(
            id: 'route-$i',
            name: 'Route $i',
            nodes: [
              LatLng(45.6 + i / 100, -73.5),
              LatLng(45.61 + i / 100, -73.4),
            ],
            distanceKm: 10,
            windingScore: 1,
            starRating: 1,
            sharpCurveCount: 1,
            centerPoint: LatLng(45.6 + i / 100, -73.5),
            distanceFromUser: 12,
          ),
      ];
    final history = RunHistoryService();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsService()),
          ChangeNotifierProvider<LocationService>.value(value: location),
          ChangeNotifierProvider<RouteService>.value(value: routes),
          ChangeNotifierProvider(
            create: (_) => DrivenRoutesService(history: history),
          ),
          ChangeNotifierProvider.value(value: SupabaseService()),
        ],
        child: const MaterialApp(home: LeanRouteFinderScreen()),
      ),
    );
    await tester.pumpAndSettle();
    final map = tester.widget<MapWidget>(find.byType(MapWidget));
    expect(map.cameraTargetPoints, hasLength(17));
    expect(map.cameraTargetSignal, greaterThan(0));
    expect(routes.mapVisualRoutes, hasLength(8));
  });
}

class _MontrealSearch extends PlaceSearchService {
  @override
  bool get isEnabled => true;
  @override
  Future<List<PlaceResult>> searchPlaces(
    String query, {
    LatLng? proximity,
    String language = 'en',
  }) async => const [
    PlaceResult(
      name: 'Montreal',
      address: 'Quebec',
      point: LatLng(45.5017, -73.5673),
      featureType: 'place',
    ),
  ];
}

Future<void> _surface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(430, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

class _DelayedLocation extends LocationService {
  _DelayedLocation(this.permission, this.fix);
  final Completer<void> permission;
  final Completer<LatLng?> fix;
  @override
  Future<void> requestPermission() async {
    await permission.future;
    hasPermission = true;
    notifyListeners();
  }

  @override
  Future<void> startTracking() async {}
  @override
  Future<LatLng?> ensureLiveLocation({
    Duration timeout = const Duration(seconds: 6),
  }) => fix.future;
}

class _QuietRoutes extends RouteService {
  List<RevvRoute> results = [];
  int fetches = 0;
  final points = <LatLng>[];
  @override
  Future<void> prefetchRouteField(
    double lat,
    double lng, {
    bool forceRefresh = false,
  }) async {
    fetches++;
    points.add(LatLng(lat, lng));
    mapVisualRoutes = results;
    notifyListeners();
  }
}

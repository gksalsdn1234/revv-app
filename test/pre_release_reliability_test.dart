import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/models/run_session.dart';
import 'package:revv_app/models/run_summary.dart';
import 'package:revv_app/models/run_telemetry_detail.dart';
import 'package:revv_app/screens/lean_drive_screen.dart';
import 'package:revv_app/screens/lean_route_finder_screen.dart';
import 'package:revv_app/screens/lean_run_summary_screen.dart';
import 'package:revv_app/services/driven_routes_service.dart';
import 'package:revv_app/services/imu_service.dart';
import 'package:revv_app/services/location_service.dart';
import 'package:revv_app/services/route_service.dart';
import 'package:revv_app/services/run_history_service.dart';
import 'package:revv_app/services/run_session_service.dart';
import 'package:revv_app/services/settings_service.dart';
import 'package:revv_app/services/supabase_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'concurrent permission callers share exactly one native request',
    () async {
      final answer = Completer<PermissionStatus>();
      var requests = 0;
      final location = LocationService(
        permissionChecker: () async => PermissionStatus.denied,
        permissionRequester: () {
          requests++;
          return answer.future;
        },
      );
      expect(location.permissionStatusLabel, '위치 권한 확인 중');
      expect(location.lastFailureReason, isNull);
      final first = location.requestPermission();
      final second = location.requestPermission();
      await Future<void>.delayed(Duration.zero);
      expect(requests, 1);
      answer.complete(PermissionStatus.granted);
      await Future.wait([first, second]);
      expect(location.hasPermission, isTrue);
      expect(location.permissionChecked, isTrue);
      location.dispose();
    },
  );

  test(
    'denied permission remains retryable and permanent denial does not request again',
    () async {
      var status = PermissionStatus.denied;
      var requests = 0;
      final location = LocationService(
        permissionChecker: () async => status,
        permissionRequester: () async {
          requests++;
          return status;
        },
      );
      await location.requestPermission();
      expect(location.permissionStatusLabel, '위치 권한 꺼짐');
      status = PermissionStatus.permanentlyDenied;
      await location.requestPermission();
      expect(requests, 1);
      expect(location.permissionStatusLabel, '설정에서 위치 권한 필요');
      location.dispose();
    },
  );

  test('manual drive retains background settings when arming ends', () async {
    final original = GeolocatorPlatform.instance;
    final platform = _PositionPlatform();
    GeolocatorPlatform.instance = platform;
    final location = LocationService()..hasPermission = true;
    await location.startTracking();
    await location.startArmedTracking();
    await location.startDriveTracking();
    expect(
      (platform.settings.last as AppleSettings).allowBackgroundLocationUpdates,
      isTrue,
    );
    await location.stopArmedTracking();
    expect(
      (platform.settings.last as AppleSettings).allowBackgroundLocationUpdates,
      isTrue,
    );
    await location.stopDriveTracking();
    expect(
      (platform.settings.last as AppleSettings).allowBackgroundLocationUpdates,
      isFalse,
    );
    location.dispose();
    GeolocatorPlatform.instance = original;
  });

  testWidgets(
    'save failure displays retry and preserves details after success',
    (tester) async {
      await _surface(tester);
      final history = _FailOnceHistory();
      final session = RunSession(
        weatherEmoji: "",
        tempDisplay: "",
        weatherDesc: "",
        startTime: DateTime.utc(2026, 9, 8),
        endTime: DateTime.utc(2026, 9, 8, 0, 2),
        maxSpeedKmh: 40,
        avgSpeedKmh: 30,
        distanceKm: 1,
        gpsPath: _route.nodes,
        route: _route,
        telemetrySamples: const [
          TelemetrySample(
            tMs: 1000,
            lat: 45,
            lng: -73,
            speedKmh: 30,
            lateralG: 0.2,
            longitudinalG: 0.1,
            driveMode: 'cruise',
          ),
        ],
      );
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<RunHistoryService>.value(value: history),
            ChangeNotifierProvider(create: (_) => LocationService()),
            ChangeNotifierProvider(create: (_) => SettingsService()),
          ],
          child: MaterialApp(home: LeanRunSummaryScreen(session: session)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Could not save'), findsOneWidget);
      expect(find.text('No session'), findsNothing);
      expect(find.text('Saved locally'), findsNothing);
      expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isFalse);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Home'))
            .onPressed,
        isNull,
      );
      final retry = find.byKey(const ValueKey('retry-run-save'));
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(find.text('Saved locally'), findsOneWidget);
      expect(history.history, hasLength(1));
      final detail = await history.loadDetail(history.history.single.id);
      expect(detail?.routeSnapshot?['nodes'], hasLength(2));
      expect(detail?.samples, hasLength(1));
    },
  );

  testWidgets(
    'cancel during hydration never starts a late session or empty report',
    (tester) async {
      await _surface(tester);
      final loaded = Completer<List<LatLng>>();
      final sessions = RunSessionService();
      final navigator = GlobalKey<NavigatorState>();
      final imu = ImuService();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => SettingsService()),
            ChangeNotifierProvider<RunSessionService>.value(value: sessions),
            ChangeNotifierProvider<ImuService>.value(value: imu),
            ChangeNotifierProvider(create: (_) => LocationService()),
          ],
          child: MaterialApp(
            navigatorKey: navigator,
            home: const Scaffold(body: Text('Route list')),
          ),
        ),
      );
      navigator.currentState!.push(
        MaterialPageRoute(
          builder: (_) => LeanDriveScreen(
            route: _route.copyWith(geometryIsOverview: true),
            simulated: true,
            routeNodesLoader: (_) => loaded.future,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(sessions.isRecording, isFalse);
      expect(find.text('Preparing drive'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('cancel-drive-start')));
      await tester.pumpAndSettle();
      loaded.complete(_route.nodes);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Route list'), findsOneWidget);
      expect(find.byType(LeanRunSummaryScreen), findsNothing);
      expect(sessions.isRecording, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      imu.dispose();
    },
  );

  testWidgets('manual start owns background tracking until one saved report', (
    tester,
  ) async {
    await _surface(tester);
    final location = _ManualLocation();
    final sessions = RunSessionService();
    final history = RunHistoryService();
    final imu = ImuService();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsService()),
          ChangeNotifierProvider<RunSessionService>.value(value: sessions),
          ChangeNotifierProvider<RunHistoryService>.value(value: history),
          ChangeNotifierProvider<ImuService>.value(value: imu),
          ChangeNotifierProvider<LocationService>.value(value: location),
        ],
        child: MaterialApp(
          home: LeanDriveScreen(
            route: _route,
            routeNodesLoader: (_) async => _route.nodes,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(location.backgroundStarts, 1);
    expect(sessions.isRecording, isTrue);
    sessions.recordPosition(45, -73, 25);
    await tester.pump();
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('End')),
    );
    await tester.pump(const Duration(seconds: 2));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(sessions.isRecording, isFalse);
    expect(location.backgroundStops, 1);
    expect(find.byType(LeanRunSummaryScreen), findsOneWidget);
    expect(history.history, hasLength(1));
    expect(find.text('Saved locally'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    imu.dispose();
  });

  testWidgets(
    'permission and GPS pending are not route-load failure or denial',
    (tester) async {
      await _surface(tester);
      final permission = Completer<void>();
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
          child: const MaterialApp(home: LeanRouteFinderScreen()),
        ),
      );
      await tester.pump();
      expect(find.text('Finding your location'), findsOneWidget);
      expect(find.text('Location permission is off'), findsNothing);
      permission.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('Finding your location'), findsOneWidget);
      expect(find.text('Could not load routes on the map.'), findsNothing);
      expect(routes.fetches, 0);
      fix.complete(null);
      await tester.pumpAndSettle();
      expect(find.text('Location is unavailable'), findsOneWidget);
      expect(find.text('Retry location'), findsOneWidget);
      expect(routes.fetches, 0);
    },
  );
}

Future<void> _surface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(375, 667));
  tester.platformDispatcher.textScaleFactorTestValue = 1.5;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

class _FailOnceHistory extends RunHistoryService {
  var attempts = 0;
  @override
  Future<RunSummary> saveSession(RunSession session) {
    if (attempts++ == 0) return Future.error(StateError('disk unavailable'));
    return super.saveSession(session);
  }
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
  int fetches = 0;
  @override
  Future<void> prefetchRouteField(
    double lat,
    double lng, {
    bool forceRefresh = false,
  }) async {
    fetches++;
  }
}

class _PositionPlatform extends GeolocatorPlatform {
  final settings = <LocationSettings>[];
  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    settings.add(locationSettings!);
    return const Stream<Position>.empty();
  }

  @override
  Future<Position?> getLastKnownPosition({
    bool forceLocationManager = false,
  }) async => Position(
    latitude: 45,
    longitude: -73,
    timestamp: DateTime.now(),
    accuracy: 5,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}

const _route = RevvRoute(
  id: 'reliability',
  name: 'Test road',
  nodes: [LatLng(45, -73), LatLng(45.01, -73.01)],
  distanceKm: 2,
  windingScore: 1,
  starRating: 1,
  sharpCurveCount: 1,
  centerPoint: LatLng(45, -73),
  distanceFromUser: 0,
);

class _ManualLocation extends LocationService {
  _ManualLocation() {
    hasPermission = true;
  }
  int backgroundStarts = 0;
  int backgroundStops = 0;
  @override
  Future<void> requestPermission() async {}
  @override
  Future<void> startTracking() async {}
  @override
  Future<void> startDriveTracking() async {
    backgroundStarts++;
  }

  @override
  Future<void> stopDriveTracking() async {
    backgroundStops++;
  }
}

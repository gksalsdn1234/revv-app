import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/screens/lean_drive_screen.dart';
import 'package:revv_app/services/imu_service.dart';
import 'package:revv_app/services/location_service.dart';
import 'package:revv_app/services/route_service.dart';
import 'package:revv_app/services/run_session_service.dart';
import 'package:revv_app/services/settings_service.dart';
import 'package:revv_app/theme/text_styles.dart';
import 'package:revv_app/widgets/copilot_start_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppText.forceSystemFonts = true;
  });

  testWidgets('copilot start sheet hides numeric route names', (tester) async {
    final settings = SettingsService();
    final route = _numericRoute(roadNames: const ['Route 329']);

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsService>.value(
        value: settings,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () =>
                    unawaited(showCopilotStartSheet(context, route: route)),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('1280740167'), findsNothing);
    expect(find.text('Route 329'), findsOneWidget);
  });

  testWidgets('external navigation closes only the copilot sheet', (
    tester,
  ) async {
    final launchedUris = <Uri>[];

    await _pumpCopilotDetail(
      tester,
      launchNavigationUrl: (uri, {required LaunchMode mode}) async {
        launchedUris.add(uri);
        return true;
      },
    );

    await tester.tap(find.text('Go detail'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open sheet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Google Maps'));
    await tester.pumpAndSettle();

    expect(launchedUris.single.scheme, 'comgooglemapsurl');
    expect(find.text('Detail screen'), findsOneWidget);
    expect(find.text('Google Maps'), findsNothing);
  });

  testWidgets('external navigation exception shows a snackbar', (tester) async {
    await _pumpCopilotDetail(
      tester,
      launchNavigationUrl: (uri, {required LaunchMode mode}) async {
        throw Exception('launcher failed');
      },
    );

    await tester.tap(find.text('Go detail'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open sheet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Google Maps'));
    await tester.pump();

    expect(find.text('Could not open a navigation app.'), findsOneWidget);
    expect(find.text('Google Maps'), findsOneWidget);
  });

  testWidgets('drive HUD hides numeric route names', (tester) async {
    final settings = SettingsService();
    final session = RunSessionService();
    final imu = ImuService();
    addTearDown(imu.dispose);
    await tester.binding.setSurfaceSize(const Size(430, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(value: settings),
          ChangeNotifierProvider<RunSessionService>.value(value: session),
          ChangeNotifierProvider<ImuService>.value(value: imu),
          ChangeNotifierProvider<LocationService>.value(
            value: _ReadyLocationService(),
          ),
        ],
        child: MaterialApp(
          home: LeanDriveScreen(
            route: _numericRoute(roadNames: const ['Route 329']),
            simulated: true,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('1280740167'), findsNothing);
    expect(find.text('Route 329'), findsOneWidget);
  });

  testWidgets('drive start stops after an unmounted permission await', (
    tester,
  ) async {
    final location = _SlowLocationService();
    final session = RunSessionService();
    final imu = ImuService();
    addTearDown(imu.dispose);
    await tester.binding.setSurfaceSize(const Size(430, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsService()),
          ChangeNotifierProvider<RunSessionService>.value(value: session),
          ChangeNotifierProvider<ImuService>.value(value: imu),
          ChangeNotifierProvider<LocationService>.value(value: location),
        ],
        child: MaterialApp(
          home: LeanDriveScreen(route: _numericRoute(), simulated: false),
        ),
      ),
    );
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    location.completeStartTracking();
    await tester.pump();

    expect(session.isRecording, isFalse);
  });
}

Future<void> _pumpCopilotDetail(
  WidgetTester tester, {
  required NavigationUrlLauncher launchNavigationUrl,
}) async {
  final settings = SettingsService();
  final route = _numericRoute();

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsService>.value(value: settings),
        ChangeNotifierProvider<RouteService>.value(value: RouteService()),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (homeContext) => Scaffold(
            body: Column(
              children: [
                const Text('Home screen'),
                FilledButton(
                  onPressed: () => Navigator.of(homeContext).push(
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        body: Builder(
                          builder: (detailContext) => Column(
                            children: [
                              const Text('Detail screen'),
                              FilledButton(
                                onPressed: () => unawaited(
                                  showCopilotStartSheet(
                                    detailContext,
                                    route: route,
                                    launchNavigationUrl: launchNavigationUrl,
                                  ),
                                ),
                                child: const Text('Open sheet'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  child: const Text('Go detail'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

RevvRoute _numericRoute({List<String> roadNames = const []}) {
  return RevvRoute(
    id: 'numeric-route',
    name: '1280740167',
    nodes: const [LatLng(45.5, -73.6), LatLng(45.6, -73.7)],
    distanceKm: 6.4,
    windingScore: 5,
    starRating: 3,
    sharpCurveCount: 4,
    centerPoint: const LatLng(45.55, -73.65),
    distanceFromUser: 3,
    tightCurveKm: 2,
    mediumCurveKm: 0.5,
    roadNames: roadNames,
  );
}

class _ReadyLocationService extends LocationService {
  _ReadyLocationService() {
    hasPermission = true;
  }

  @override
  LatLng? get bestKnownLatLng => const LatLng(45.5, -73.6);
}

class _SlowLocationService extends LocationService {
  final Completer<void> _startTracking = Completer<void>();

  _SlowLocationService() {
    hasPermission = true;
  }

  @override
  Future<void> requestPermission() async {}

  @override
  Future<void> startTracking() => _startTracking.future;

  @override
  Future<LatLng?> ensureLiveLocation({
    Duration timeout = const Duration(seconds: 6),
  }) async => const LatLng(45.5, -73.6);

  void completeStartTracking() {
    if (!_startTracking.isCompleted) _startTracking.complete();
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/screens/lean_route_detail_screen.dart';
import 'package:revv_app/services/settings_service.dart';
import 'package:revv_app/ui/route_share_card_content.dart';
import 'package:url_launcher/url_launcher.dart';

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
  await _pumpRouteAtSize(tester, route, const Size(390, 2200));
}

Future<void> _pumpRouteAtSize(
  WidgetTester tester,
  RevvRoute route,
  Size size,
) async {
  await tester.binding.setSurfaceSize(size);
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

  test('street view URI uses middle route node and bearing', () {
    final target = streetViewTargetForRoute(_route());

    expect(target.point.lat, 45.0100);
    expect(target.point.lng, -72.9900);
    expect(target.bearing, closeTo(313, 1));
    expect(
      buildStreetViewAppUri(target).toString(),
      'google.streetview:cbll=45.010000,-72.990000&cbp=0,313,0,0,0',
    );
    expect(
      buildStreetViewWebUri(target).toString(),
      contains('map_action=pano'),
    );
  });

  testWidgets('street view failure shows snackbar', (tester) async {
    final launched = <Uri>[];
    await tester.binding.setSurfaceSize(const Size(390, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsService>.value(
        value: SettingsService(),
        child: MaterialApp(
          home: LeanRouteDetailScreen(
            route: _route(),
            urlLauncher: (url, {mode = LaunchMode.platformDefault}) async {
              launched.add(url);
              return false;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Street View'));
    await tester.pump();

    expect(launched, hasLength(2));
    expect(find.text('Could not open Street View.'), findsOneWidget);
  });

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
      find.text('Tight 1.4km · Medium 2.1km · Straight/gentle 8.5km'),
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
    expect(find.text('LOOP'), findsWidgets);
    expect(find.text('Flow'), findsNothing);

    _expectNoForbiddenSafetyWords(
      [
        'Delta 58m',
        'Tight 1.4km · Medium 2.1km · Straight/gentle 8.5km',
        'Longest winding flow 1.8km',
        'Posted speed-limit sections 50 — follow roadside signs',
        'Nearby: Cafe Nord · Belvedere Est · Lookout',
        'REVV runs 5',
        'LOOP',
      ].join(' | '),
    );
  });

  testWidgets(
    'route detail checks an invite draft before sharing it through the presenter',
    (tester) async {
      String? sharedText;
      DriveInviteDraft? sharedDraft;
      final settings = SettingsService();

      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsService>.value(
          value: settings,
          child: MaterialApp(
            home: LeanRouteDetailScreen(
              route: _route(sharpCurveCount: 7),
              routeInvitePresenter: (text, draft) async {
                sharedText = text;
                sharedDraft = draft;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Share route'));
      await tester.pumpAndSettle();

      expect(sharedText, isNull);
      expect(find.text('Share invite'), findsOneWidget);
      expect(find.text('This weekend · time TBD'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('invite-meeting-area-selector')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Near Old Port').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('share-invite-draft')));
      await tester.pumpAndSettle();

      expect(sharedText, contains('Open in Google Maps:'));
      expect(sharedText, contains('REVV route'));
      expect(sharedText, isNot(contains('Near Old Port')));
      expect(sharedDraft, isNotNull);
      expect(sharedDraft!.meetingArea, DriveInviteMeetingArea.oldPort);
      expect(find.byType(LeanRouteDetailScreen), findsOneWidget);
    },
  );

  testWidgets(
    'route detail does not share when the invite preview is dismissed',
    (tester) async {
      var presenterCalls = 0;
      final settings = SettingsService();

      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsService>.value(
          value: settings,
          child: MaterialApp(
            home: LeanRouteDetailScreen(
              route: _route(sharpCurveCount: 7),
              routeInvitePresenter: (_, _) async => presenterCalls++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Share route'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('dismiss-invite-preview')));
      await tester.pumpAndSettle();

      expect(presenterCalls, 0);
      expect(find.byType(LeanRouteDetailScreen), findsOneWidget);
    },
  );

  testWidgets(
    'route detail keeps the drive in place when invite sharing fails',
    (tester) async {
      final settings = SettingsService();

      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsService>.value(
          value: settings,
          child: MaterialApp(
            home: LeanRouteDetailScreen(
              route: _route(sharpCurveCount: 7),
              routeInvitePresenter: (_, _) async => throw StateError('share'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Share route'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('share-invite-draft')));
      await tester.pumpAndSettle();

      expect(
        find.text('Could not share this route. Try again.'),
        findsOneWidget,
      );
      expect(find.byType(LeanRouteDetailScreen), findsOneWidget);
    },
  );
  testWidgets('route detail hides enrichment sections when data is empty', (
    tester,
  ) async {
    await _pumpRoute(tester, _route());

    expect(find.text('ELEVATION PROFILE'), findsNothing);
    expect(find.text('CURVE MIX'), findsNothing);
    expect(find.text('ROAD INFO'), findsNothing);
    expect(find.text('JOURNEY INFO'), findsNothing);
    expect(find.text('Flow'), findsNothing);
  });

  testWidgets('route detail stays readable when server fields are empty', (
    tester,
  ) async {
    final route = _route(
      tightCurveKm: 1.1,
      mediumCurveKm: 1.6,
      maxContinuousKm: 1.2,
      sharpCurveCount: 5,
    );

    await _pumpRouteAtSize(tester, route, const Size(390, 844));

    expect(find.byKey(const ValueKey('route-detail-hero')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('route-detail-stat-strip')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('route-detail-curve-mix')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('route-detail-copilot-headline')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('route-detail-drive-environment')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('route-detail-expansion')),
      findsOneWidget,
    );
    expect(find.text('ELEVATION PROFILE'), findsNothing);
    expect(find.text('ROAD INFO'), findsNothing);
    expect(find.text('JOURNEY INFO'), findsNothing);
    expect(find.text('Few stop controls'), findsOneWidget);

    for (final key in const [
      ValueKey('route-detail-hero'),
      ValueKey('route-detail-stat-strip'),
      ValueKey('route-detail-curve-mix'),
    ]) {
      expect(tester.getBottomLeft(find.byKey(key)).dy, lessThan(844));
    }

    expect(
      find.text('Start is 2.5km away. Navigate there, then enter the route.'),
      findsNothing,
    );
    await tester.ensureVisible(find.text('Details'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(
      find.text('Start is 2.5km away. Navigate there, then enter the route.'),
      findsOneWidget,
    );

    _expectNoForbiddenSafetyWords(
      [
        'Detail Route',
        'Tight 1.1km · Medium 1.6km · Straight/gentle 9.3km',
        'Longest winding flow 1.2km',
        'Few stop controls',
        'Details',
      ].join(' | '),
    );
  });
}

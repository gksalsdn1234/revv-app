import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:revv_app/labs/walkie/walkie_ptt_controller.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/screens/lean_drive_screen.dart';
import 'package:revv_app/services/crew_channel_service.dart';
import 'package:revv_app/services/imu_service.dart';
import 'package:revv_app/services/location_service.dart';
import 'package:revv_app/services/ptt_service.dart';
import 'package:revv_app/services/run_session_service.dart';
import 'package:revv_app/services/settings_service.dart';
import 'package:revv_app/services/route_turn_service.dart';
import 'package:revv_app/services/voice_briefing_service.dart';
import 'package:revv_app/theme/text_styles.dart';
import 'package:revv_app/widgets/map_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
// ignore: depend_on_referenced_packages
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

class _FakeCrew extends CrewChannelService {
  _FakeCrew({required this.joined});
  final bool joined;
  @override
  bool get isJoined => joined;
  @override
  String? get channelId => joined ? 'chan-1' : null;
}

class _RecordingController implements WalkiePttController {
  @override
  final ValueNotifier<bool> channelBusy = ValueNotifier(false);

  @override
  final ValueNotifier<double> micLevel = ValueNotifier(0);

  @override
  final ValueNotifier<PttConnectionState> connectionState = ValueNotifier(
    PttConnectionState.connected,
  );

  int connectCount = 0;
  int disconnectCount = 0;
  int startCount = 0;
  int stopCount = 0;
  String? lastChannel;

  @override
  Future<void> connect(String channelId) async {
    connectCount++;
    lastChannel = channelId;
  }

  @override
  Future<void> disconnect() async => disconnectCount++;

  @override
  Future<void> startTalking(String channelId) async {
    startCount++;
    lastChannel = channelId;
  }

  @override
  Future<void> stopTalking() async => stopCount++;

  @override
  Future<void> dispose() async {}
}

const _route = RevvRoute(
  id: 'r1',
  name: 'Chemin Test',
  nodes: [LatLng(45.5, -73.6), LatLng(45.55, -73.65), LatLng(45.6, -73.7)],
  distanceKm: 8,
  windingScore: 5,
  starRating: 3,
  sharpCurveCount: 4,
  centerPoint: LatLng(45.55, -73.65),
  distanceFromUser: 2,
);

Future<void> _pump(
  WidgetTester tester, {
  required bool enabled,
  required bool joined,
  _RecordingController? controller,
  RevvRoute route = _route,
  DriveRouteNodesLoader? routeNodesLoader,
  DriveRouteGeometryMatcher? routeGeometryMatcher,
  RouteTurnService? routeTurnService,
}) async {
  SharedPreferences.setMockInitialValues({});
  AppText.forceSystemFonts = true;
  await tester.binding.setSurfaceSize(const Size(430, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<LocationService>(
          create: (_) => LocationService(),
        ),
        ChangeNotifierProvider<RunSessionService>(
          create: (_) => RunSessionService(),
        ),
        ChangeNotifierProvider<SettingsService>(
          create: (_) => SettingsService(),
        ),
        ChangeNotifierProvider<ImuService>(create: (_) => ImuService()),
        Provider<WalkiePttController>.value(
          value: controller ?? _RecordingController(),
        ),
      ],
      child: MaterialApp(
        home: LeanDriveScreen(
          route: route,
          simulated: true,
          walkieEnabledOverride: enabled,
          crewChannelOverride: _FakeCrew(joined: joined),
          pttControllerOverride: controller,
          voiceOverride: VoiceBriefingService(speak: (_, _) async {}),
          routeNodesLoader: routeNodesLoader,
          routeGeometryMatcher: routeGeometryMatcher,
          routeTurnService: routeTurnService,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('drive screen enables and disables wakelock', (tester) async {
    final platform = _RecordingWakelockPlatform();
    final previous = wakelockPlusPlatformInstance;
    wakelockPlusPlatformInstance = platform;
    addTearDown(() => wakelockPlusPlatformInstance = previous);

    await _pump(tester, enabled: false, joined: false);
    await tester.pump();
    expect(platform.toggles, contains(true));

    await tester.tap(find.text('End'));
    await tester.pump();
    expect(find.text('Hold to end'), findsOneWidget);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Hold to end')),
    );
    await tester.pump(const Duration(milliseconds: 1500));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      platform.toggles.where((value) => !value).length,
      greaterThanOrEqualTo(2),
    );
  });

  testWidgets('no PTT button when the walkie flag is off', (tester) async {
    await _pump(tester, enabled: false, joined: true);
    expect(find.byIcon(Icons.mic_rounded), findsNothing);
  });

  testWidgets('no PTT button when not joined to a channel', (tester) async {
    await _pump(tester, enabled: true, joined: false);
    expect(find.byIcon(Icons.mic_rounded), findsNothing);
  });

  testWidgets('PTT button shows and hold/release drives the controller', (
    tester,
  ) async {
    final controller = _RecordingController();
    await _pump(tester, enabled: true, joined: true, controller: controller);

    expect(find.byIcon(Icons.mic_rounded), findsOneWidget);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byIcon(Icons.mic_rounded)),
    );
    await tester.pump();
    expect(controller.startCount, 1);
    expect(controller.lastChannel, 'chan-1');

    await gesture.up();
    await tester.pump();
    expect(controller.stopCount, 1);
  });

  testWidgets('tap cancel also stops talking', (tester) async {
    final controller = _RecordingController();
    await _pump(tester, enabled: true, joined: true, controller: controller);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byIcon(Icons.mic_rounded)),
    );
    await tester.pump();
    await gesture.cancel();
    await tester.pump();
    expect(controller.stopCount, 1);
  });

  testWidgets('busy channel disables PTT start', (tester) async {
    final controller = _RecordingController();
    controller.channelBusy.value = true;
    await _pump(tester, enabled: true, joined: true, controller: controller);

    expect(find.text('RX'), findsOneWidget);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byIcon(Icons.mic_rounded)),
    );
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(controller.startCount, 0);
    expect(controller.stopCount, 0);
  });

  testWidgets('reconnecting disables PTT start and shows spinner', (
    tester,
  ) async {
    final controller = _RecordingController();
    controller.connectionState.value = PttConnectionState.reconnecting;
    await _pump(tester, enabled: true, joined: true, controller: controller);

    expect(find.text('Reconnecting…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byIcon(Icons.mic_rounded)),
    );
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(controller.startCount, 0);
    expect(controller.stopCount, 0);
  });

  testWidgets('starting drive hydrates sparse route nodes once', (tester) async {
    int loadCount = 0;
    await _pump(
      tester,
      enabled: false,
      joined: false,
      routeNodesLoader: (routeId) async {
        loadCount++;
        expect(routeId, 'r1');
        return const [
          LatLng(45.5, -73.6),
          LatLng(45.5002, -73.6002),
          LatLng(45.5004, -73.6004),
        ];
      },
    );

    expect(loadCount, 1);
  });

  testWidgets('starting drive keeps dense route nodes without hydration', (
    tester,
  ) async {
    int loadCount = 0;
    const denseRoute = RevvRoute(
      id: 'dense',
      name: 'Dense',
      nodes: [
        LatLng(45.5, -73.6),
        LatLng(45.5002, -73.6002),
        LatLng(45.5004, -73.6004),
      ],
      distanceKm: 1,
      windingScore: 5,
      starRating: 3,
      sharpCurveCount: 1,
      centerPoint: LatLng(45.5002, -73.6002),
      distanceFromUser: 1,
    );

    await _pump(
      tester,
      enabled: false,
      joined: false,
      route: denseRoute,
      routeNodesLoader: (_) async {
        loadCount++;
        return const [];
      },
    );

    expect(loadCount, 0);
  });

  testWidgets('matched geometry reloads turn steps on the same snapshot', (
    tester,
  ) async {
    final turns = _RecordingTurnService(
      client: _FakeTurnClient((request) async {
        final isMatchedSnapshot = request.url.pathSegments.last.contains(
          '-73.60003,45.50003',
        );
        return http.Response(
          _turnFixture(isMatchedSnapshot ? 'roundabout' : 'fork'),
          200,
        );
      }),
    );
    const route = RevvRoute(
      id: 'matched-route',
      name: 'Matched route',
      // 총 길이가 45m 이하이면 시작 즉시 완주 판정이라 턴 배너가 뜨지 않는다.
      nodes: [
        LatLng(45.5000, -73.6000),
        LatLng(45.5050, -73.6050),
        LatLng(45.5100, -73.6100),
      ],
      distanceKm: 1,
      windingScore: 5,
      starRating: 3,
      sharpCurveCount: 1,
      centerPoint: LatLng(45.5001, -73.6001),
      distanceFromUser: 1,
    );
    // Map matching은 도로에 스냅하는 것이므로 원본에서 수십 m 수준으로만 어긋난다.
    // 수백 m 이상 옮기면 오프루트로 판정돼 턴 대신 이탈 배너가 뜬다.
    const matched = [
      LatLng(45.50003, -73.60003),
      LatLng(45.50503, -73.60503),
      LatLng(45.51003, -73.61003),
    ];

    await _pump(
      tester,
      enabled: false,
      joined: false,
      route: route,
      routeNodesLoader: (_) async => const [],
      routeTurnService: turns,
      routeGeometryMatcher: (_) async => matched,
    );
    await tester.pump();
    await tester.pump();

    final map = tester.widget<MapWidget>(find.byType(MapWidget));
    expect(map.routePolyline, same(matched));
    expect(turns.requestedSnapshots, hasLength(2));
    expect(
      turns.requestedSnapshots.last
          .map((point) => '${point.lat},${point.lng}'),
      orderedEquals(matched.map((point) => '${point.lat},${point.lng}')),
    );
    expect(turns.generatedSteps, hasLength(2));
    final reloadedSteps = turns.generatedSteps.singleWhere(
      (steps) => steps.last.maneuverType == 'roundabout',
    );
    expect(reloadedSteps.last.distanceFromStartM, 720.0);
  });
}

class _RecordingTurnService extends RouteTurnService {
  _RecordingTurnService({required super.client}) : super(accessToken: 'token');

  final List<List<LatLng>> requestedSnapshots = [];
  final List<List<NavStep>> generatedSteps = [];

  @override
  Future<List<NavStep>> fetchSteps(List<LatLng> routeNodes) async {
    requestedSnapshots.add(List<LatLng>.unmodifiable(routeNodes));
    final steps = await super.fetchSteps(routeNodes);
    generatedSteps.add(steps);
    return steps;
  }
}

class _FakeTurnClient extends http.BaseClient {
  _FakeTurnClient(this.handler);

  final Future<http.Response> Function(http.Request request) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await handler(request as http.Request);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
    );
  }
}

/// Mapbox의 `distance`는 해당 maneuver에서 다음 maneuver까지의 거리다.
/// 따라서 depart 뒤의 실제 maneuver는 누적 720m에서 재생성된다.
String _turnFixture(String maneuverType) => jsonEncode({
  'routes': [
    {
      'legs': [
        {
          'steps': [
            {
              'distance': 720.0,
              'maneuver': {
                'type': 'depart',
                'location': [-73.60003, 45.50003],
              },
            },
            {
              'distance': 50.0,
              'maneuver': {
                'type': maneuverType,
                'location': [-73.60013, 45.50013],
              },
            },
          ],
        },
      ],
    },
  ],
});

class _RecordingWakelockPlatform extends WakelockPlusPlatformInterface {
  final List<bool> toggles = [];

  @override
  Future<void> toggle({required bool enable}) async => toggles.add(enable);

  @override
  Future<bool> get enabled async => toggles.isNotEmpty && toggles.last;
}

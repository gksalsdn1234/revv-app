import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:revv_app/labs/walkie/walkie_ptt_controller.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/screens/lean_drive_screen.dart';
import 'package:revv_app/services/crew_channel_service.dart';
import 'package:revv_app/services/imu_service.dart';
import 'package:revv_app/services/location_service.dart';
import 'package:revv_app/services/run_session_service.dart';
import 'package:revv_app/services/settings_service.dart';
import 'package:revv_app/theme/text_styles.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
}) async {
  SharedPreferences.setMockInitialValues({});
  AppText.forceSystemFonts = true;
  await tester.binding.setSurfaceSize(const Size(430, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<LocationService>(create: (_) => LocationService()),
        ChangeNotifierProvider<RunSessionService>(create: (_) => RunSessionService()),
        ChangeNotifierProvider<SettingsService>(create: (_) => SettingsService()),
        ChangeNotifierProvider<ImuService>(create: (_) => ImuService()),
        Provider<WalkiePttController>.value(
          value: controller ?? _RecordingController(),
        ),
      ],
      child: MaterialApp(
        home: LeanDriveScreen(
          route: _route,
          simulated: true,
          walkieEnabledOverride: enabled,
          crewChannelOverride: _FakeCrew(joined: joined),
          pttControllerOverride: controller,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
}

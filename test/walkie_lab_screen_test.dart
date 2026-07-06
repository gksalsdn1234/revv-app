import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/core/app_language.dart';
import 'package:revv_app/labs/walkie/walkie_lab_screen.dart';
import 'package:revv_app/services/crew_channel_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('initial state is not joined and keeps microphone disabled', (
    tester,
  ) async {
    final ptt = _FakeWalkiePttController();
    await tester.pumpWalkie(ptt: ptt);

    expect(find.text('Not joined'), findsOneWidget);
    expect(find.text('Create'), findsOneWidget);
    expect(find.text('Join'), findsOneWidget);
    expect(find.text('Leave'), findsOneWidget);
    expect(find.text('0 online'), findsOneWidget);
    expect(find.text('Locked'), findsOneWidget);

    await tester.pressMic();
    expect(ptt.startedChannels, isEmpty);
    expect(ptt.stopCount, 0);
  });

  testWidgets('press and release call startTalking then stopTalking', (
    tester,
  ) async {
    final ptt = _FakeWalkiePttController();
    await tester.pumpWalkie(ptt: ptt);
    await tester.joinRoom();
    await tester.ensureVisible(_micFinder);
    await tester.pump();

    final gesture = await tester.startGesture(tester.getCenter(_micFinder));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(ptt.startedChannels, ['channel-1']);
    expect(ptt.stopCount, 1);
  });

  testWidgets('joining connects receive audio before pressing the microphone', (
    tester,
  ) async {
    final ptt = _FakeWalkiePttController();
    await tester.pumpWalkie(ptt: ptt);
    await tester.joinRoom();

    expect(ptt.connectedChannels, ['channel-1']);
    expect(ptt.startedChannels, isEmpty);
  });

  testWidgets('leaving disconnects receive audio', (tester) async {
    final ptt = _FakeWalkiePttController();
    await tester.pumpWalkie(ptt: ptt);
    await tester.joinRoom();
    await tester.leaveRoom();

    expect(ptt.disconnectCount, 1);
  });

  testWidgets('cancel stops talking', (tester) async {
    final ptt = _FakeWalkiePttController();
    await tester.pumpWalkie(ptt: ptt);
    await tester.joinRoom();
    await tester.ensureVisible(_micFinder);
    await tester.pump();

    final gesture = await tester.startGesture(tester.getCenter(_micFinder));
    await tester.pump(const Duration(milliseconds: 150));
    await gesture.cancel();
    await tester.pump();

    expect(ptt.startedChannels, ['channel-1']);
    expect(ptt.stopCount, 1);
  });

  testWidgets('layout has no overflow at 320px width', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWalkie(ptt: _FakeWalkiePttController());
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}

final _micFinder = find.byKey(const ValueKey('walkieMicButton'));

extension on WidgetTester {
  Future<void> pumpWalkie({required _FakeWalkiePttController ptt}) async {
    await pumpWidget(
      MaterialApp(
        home: WalkieLabScreen(
          crewChannelService: CrewChannelService(supabase: _FakeCrewSupabase()),
          pttController: ptt,
          language: AppLanguage.english,
        ),
      ),
    );
    await pump();
  }

  Future<void> joinRoom() async {
    await enterText(find.widgetWithText(TextField, 'Join code'), 'ABCD2345');
    await tap(find.text('Join'));
    await pumpAndSettle();
    expect(find.text('Connected'), findsOneWidget);
  }

  Future<void> leaveRoom() async {
    await tap(find.text('Leave'));
    await pumpAndSettle();
    expect(find.text('Not joined'), findsOneWidget);
  }

  Future<void> pressMic() async {
    await ensureVisible(_micFinder);
    await pump();
    final gesture = await startGesture(getCenter(_micFinder));
    await pump();
    await gesture.up();
    await pump();
  }
}

class _FakeWalkiePttController implements WalkiePttController {
  final connectedChannels = <String>[];
  final startedChannels = <String>[];
  var disconnectCount = 0;
  var stopCount = 0;

  @override
  Future<void> connect(String channelId) async {
    connectedChannels.add(channelId);
  }

  @override
  Future<void> disconnect() async {
    disconnectCount += 1;
  }

  @override
  Future<void> startTalking(String channelId) async {
    startedChannels.add(channelId);
  }

  @override
  Future<void> stopTalking() async {
    stopCount += 1;
  }

  @override
  Future<void> dispose() async {}
}

class _FakeCrewSupabase implements CrewChannelSupabase {
  @override
  bool isReady = true;

  @override
  String? uid = 'member-1';

  final subscriptions = <_FakePresenceSubscription>[];

  @override
  Future<Map<String, dynamic>> createChannelRow(String name) async {
    return {'id': 'channel-1', 'code': 'ABCD2345'};
  }

  @override
  Future<Map<String, dynamic>> joinCrewChannel(
    String code,
    String displayName,
  ) async {
    return {
      'channel_id': 'channel-1',
      'member_id': 'member-1',
      'display_name': displayName.isEmpty ? 'Crew 1' : displayName,
    };
  }

  @override
  Future<void> deleteMember(String channelId, String memberId) async {}

  @override
  CrewPresenceSubscription openPresence(
    String channelId, {
    required String presenceKey,
  }) {
    final subscription = _FakePresenceSubscription();
    subscriptions.add(subscription);
    return subscription;
  }
}

class _FakePresenceSubscription implements CrewPresenceSubscription {
  VoidCallback? _onSync;

  @override
  void onSync(VoidCallback callback) {
    _onSync = callback;
  }

  @override
  Future<void> subscribe() async {}

  @override
  Future<void> track(Map<String, dynamic> payload) async {
    _onSync?.call();
  }

  @override
  Future<void> untrack() async {}

  @override
  Future<void> unsubscribe() async {}

  @override
  List<CrewPresenceRecord> presenceState() {
    return const [
      (memberId: 'member-1', payload: {'display_name': 'Crew 1'}),
      (memberId: 'member-2', payload: {'display_name': 'Alex'}),
    ];
  }
}

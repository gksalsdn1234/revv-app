import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/core/app_language.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/services/route_turn_service.dart';
import 'package:revv_app/services/voice_briefing_service.dart';
import 'package:revv_app/ui/route_drive_cue.dart';

DriveCurveCue cue({
  double distanceM = 200,
  int severity = 2,
  int curveCountAhead = 1,
  double? nextGapM,
  String direction = '우측',
  String intensity = '타이트',
}) {
  return DriveCurveCue(
    label: '$direction $intensity',
    detail: '',
    directionLabel: direction,
    intensityLabel: intensity,
    headline: '',
    rhythmLine: '',
    icon: Icons.turn_right_rounded,
    distanceM: distanceM,
    nextGapM: nextGapM,
    curveCountAhead: curveCountAhead,
    horizonM: distanceM + 400,
    severity: severity,
  );
}

class _FakeVoiceTtsClient implements VoiceTtsClient {
  _FakeVoiceTtsClient({required this.voices, this.firstSpeakGate});

  final Object? voices;
  final Completer<void>? firstSpeakGate;
  final selectedVoices = <Map<String, String>>[];
  final spoken = <String>[];
  final languages = <String>[];
  final speechRates = <double>[];
  final pitches = <double>[];
  int getVoicesCount = 0;

  @override
  Future<void> configureAudioSession() async {}

  @override
  Future<void> setSpeechRate(double rate) async => speechRates.add(rate);

  @override
  Future<void> setPitch(double pitch) async => pitches.add(pitch);

  @override
  Future<void> setLanguage(String language) async => languages.add(language);

  @override
  Future<Object?> getVoices() async {
    getVoicesCount++;
    return voices;
  }

  @override
  Future<void> setVoice(Map<String, String> voice) async {
    selectedVoices.add(voice);
  }

  @override
  Future<void> speak(String text) async {
    spoken.add(text);
    if (spoken.length == 1) await firstSpeakGate?.future;
  }

  @override
  Future<void> stop() async {}
}

void main() {
  const forbidden = ['속도', '스릴', '짜릿', '과속', 'MAX', 'BEST', 'PEAK', '어택'];

  late List<String> spoken;
  late DateTime now;
  late VoiceBriefingService voice;

  setUp(() {
    spoken = [];
    now = DateTime(2026, 7, 3, 10, 0, 0);
    voice = VoiceBriefingService(
      speak: (text, _) async => spoken.add(text),
      clock: () => now,
    );
  });

  test('speaks a tight curve once inside the 300m window', () {
    voice.onCoPilotCue(
      curveCue: cue(distanceM: 300),
      language: AppLanguage.korean,
      muted: false,
    );
    voice.onCoPilotCue(
      curveCue: cue(distanceM: 200),
      language: AppLanguage.korean,
      muted: false,
    );
    voice.onCoPilotCue(
      curveCue: cue(distanceM: 90),
      language: AppLanguage.korean,
      muted: false,
    );

    expect(spoken, hasLength(1));
    expect(spoken.first, '300, 우측 급커브');
  });

  test('stays silent when muted or severity is low', () {
    voice.onCoPilotCue(
      curveCue: cue(),
      language: AppLanguage.korean,
      muted: true,
    );
    voice.onCoPilotCue(
      curveCue: cue(severity: 1),
      language: AppLanguage.korean,
      muted: false,
    );
    voice.onCoPilotCue(
      curveCue: cue(severity: 2, curveCountAhead: 0), // 이탈/상태 큐
      language: AppLanguage.korean,
      muted: false,
    );
    expect(spoken, isEmpty);
  });

  test('ignores curves outside the speaking window', () {
    voice.onCoPilotCue(
      curveCue: cue(distanceM: 700),
      language: AppLanguage.korean,
      muted: false,
    );
    voice.onCoPilotCue(
      curveCue: cue(distanceM: 30),
      language: AppLanguage.korean,
      muted: false,
    );
    expect(spoken, isEmpty);
  });

  test('combo pattern announces the chain', () {
    voice.onCoPilotCue(
      curveCue: cue(curveCountAhead: 4, nextGapM: 150),
      language: AppLanguage.korean,
      muted: false,
    );
    expect(spoken.single, contains('좌우 커브'));
    expect(spoken.single, contains('4개'));
  });

  test('medium curves speak only when they form a meaningful sequence', () {
    voice.onCoPilotCue(
      curveCue: cue(severity: 1, intensity: '중간', curveCountAhead: 1),
      language: AppLanguage.korean,
      muted: false,
    );
    expect(spoken, isEmpty);

    voice.onCoPilotCue(
      curveCue: cue(
        severity: 1,
        intensity: '중간',
        curveCountAhead: 4,
        nextGapM: 150,
      ),
      language: AppLanguage.korean,
      muted: false,
    );

    expect(spoken.single, '200, 우측 커브. 좌우 커브 4개');
  });

  test('a close pair of medium curves is worth briefing', () {
    voice.onCoPilotCue(
      curveCue: cue(
        severity: 1,
        intensity: '중간',
        curveCountAhead: 2,
        nextGapM: 180,
      ),
      language: AppLanguage.korean,
      muted: false,
    );

    expect(spoken.single, '200, 우측 커브. 연속 커브 2개');
  });

  test('curve wording changes with tight and hairpin severity', () {
    expect(
      voice.buildPhrase(cue(), language: AppLanguage.korean),
      '200, 우측 급커브',
    );
    expect(
      voice.buildPhrase(
        cue(severity: 3, intensity: '헤어핀', direction: '좌측'),
        language: AppLanguage.korean,
      ),
      '200, 좌측 급회전',
    );
  });

  test('curve direction and intensity use natural localized word order', () {
    final mediumPair = cue(
      severity: 1,
      intensity: 'Medium',
      direction: 'Right',
      curveCountAhead: 2,
      nextGapM: 180,
    );

    expect(
      voice.buildPhrase(mediumPair, language: AppLanguage.english),
      '200, right turn. 2-curve sequence',
    );
    expect(
      voice.buildPhrase(mediumPair, language: AppLanguage.french),
      '200, virage à droite. série de 2 virages',
    );
  });

  test('hairpin gets the prepare-early phrasing', () {
    voice.onCoPilotCue(
      curveCue: cue(severity: 3, intensity: '헤어핀', direction: '좌측'),
      language: AppLanguage.korean,
      muted: false,
    );
    expect(spoken.single, '200, 좌측 급회전');
  });

  test('cooldown suppresses a second callout within 5 seconds', () {
    voice.onCoPilotCue(
      curveCue: cue(distanceM: 200),
      language: AppLanguage.korean,
      muted: false,
    );
    // 커브 통과(큐 소멸) 후 곧바로 새 커브 — 쿨다운에 걸림
    voice.onCue(null, language: AppLanguage.korean, muted: false);
    now = now.add(const Duration(seconds: 4));
    voice.onCoPilotCue(
      curveCue: cue(distanceM: 250),
      language: AppLanguage.korean,
      muted: false,
    );
    expect(spoken, hasLength(1));

    now = now.add(const Duration(seconds: 2));
    voice.onCoPilotCue(
      curveCue: cue(distanceM: 240),
      language: AppLanguage.korean,
      muted: false,
    );
    expect(spoken, hasLength(2));
  });

  test('re-arms for a new farther curve after passing the spoken one', () {
    voice.onCoPilotCue(
      curveCue: cue(distanceM: 150),
      language: AppLanguage.korean,
      muted: false,
    );
    now = now.add(const Duration(seconds: 10));
    // 발화한 커브(150m)보다 충분히 먼 새 커브
    voice.onCoPilotCue(
      curveCue: cue(distanceM: 310),
      language: AppLanguage.korean,
      muted: false,
    );
    expect(spoken, hasLength(2));
  });

  test('long clear gap adds no filler', () {
    // 첫 큐 관측 (발화 없이 창 밖)
    voice.onCoPilotCue(
      curveCue: cue(distanceM: 700),
      language: AppLanguage.korean,
      muted: false,
    );
    // 20초 이상 큐 없음 → 긴 흐름 구간
    now = now.add(const Duration(seconds: 25));
    voice.onCoPilotCue(
      curveCue: cue(distanceM: 300),
      language: AppLanguage.korean,
      muted: false,
    );
    expect(spoken.single, '300, 우측 급커브');
  });

  test('merges nearby TBT and curve events into one pacenote', () {
    final phrase = voice.buildCoPilotPhrase(
      language: AppLanguage.korean,
      navStep: const NavStep(
        sequence: 1,
        maneuverType: 'fork',
        modifier: 'right',
        location: LatLng(45, -73),
        distanceFromStartM: 100,
        segmentDistanceM: 200,
      ),
      navDistanceM: 300,
      curveCue: cue(distanceM: 120, direction: '좌측'),
    );

    expect(phrase, '300, 우측 갈림길. 좌측 급커브');
    expect(phrase, isNot(contains('미터 앞')));
    expect(phrase, isNot(contains('하세요')));
  });

  test('winding mode speaks the curve before a nearby maneuver', () {
    final phrase = voice.buildCoPilotPhrase(
      language: AppLanguage.korean,
      navStep: const NavStep(
        sequence: 1,
        maneuverType: 'fork',
        modifier: 'right',
        location: LatLng(45, -73),
        distanceFromStartM: 100,
        segmentDistanceM: 200,
      ),
      navDistanceM: 300,
      curveCue: cue(distanceM: 120, direction: '좌측'),
      preferCurve: true,
    );

    expect(phrase, '120, 좌측 급커브. 우측 갈림길');
  });

  test('combined speech marks the included curve as already spoken', () {
    const nav = NavStep(
      sequence: 1,
      maneuverType: 'fork',
      modifier: 'right',
      location: LatLng(45, -73),
      distanceFromStartM: 100,
      segmentDistanceM: 200,
    );
    final curve = cue(distanceM: 120, direction: '좌측');
    voice.onCoPilotCue(
      navStep: nav,
      navDistanceM: 300,
      curveCue: curve,
      language: AppLanguage.korean,
      muted: false,
    );
    now = now.add(const Duration(seconds: 9));
    voice.onCoPilotCue(
      curveCue: curve,
      language: AppLanguage.korean,
      muted: false,
    );

    expect(spoken, hasLength(1));
  });

  test('short straight navigation stays silent without a curve', () {
    voice.onCoPilotCue(
      navStep: const NavStep(
        sequence: 1,
        maneuverType: 'continue',
        modifier: 'straight',
        location: LatLng(45, -73),
        distanceFromStartM: 500,
        segmentDistanceM: 400,
      ),
      navDistanceM: 300,
      language: AppLanguage.korean,
      muted: false,
    );

    expect(spoken, isEmpty);
  });

  test('short straight navigation yields to detailed curve briefing', () {
    voice.onCoPilotCue(
      navStep: const NavStep(
        sequence: 1,
        maneuverType: 'continue',
        modifier: 'straight',
        location: LatLng(45, -73),
        distanceFromStartM: 500,
        segmentDistanceM: 400,
      ),
      navDistanceM: 300,
      curveCue: cue(
        distanceM: 220,
        direction: '우측',
        intensity: '타이트',
        curveCountAhead: 4,
        nextGapM: 150,
      ),
      language: AppLanguage.korean,
      muted: false,
    );

    expect(spoken.single, '220, 우측 급커브. 좌우 커브 4개');
    expect(spoken.single, isNot(contains('직진')));
  });

  test('a significant curve leads when a long straight overlaps it', () {
    voice.onCoPilotCue(
      navStep: const NavStep(
        sequence: 1,
        maneuverType: 'continue',
        modifier: 'straight',
        location: LatLng(45, -73),
        distanceFromStartM: 500,
        segmentDistanceM: 1200,
      ),
      navDistanceM: 300,
      curveCue: cue(
        distanceM: 220,
        direction: '우측',
        intensity: '타이트',
        curveCountAhead: 4,
        nextGapM: 150,
      ),
      language: AppLanguage.korean,
      muted: false,
    );

    expect(spoken.single, '220, 우측 급커브. 좌우 커브 4개');
    expect(spoken.single, isNot(contains('직진')));
  });

  test('long straight navigation is announced once with its length', () {
    const step = NavStep(
      sequence: 1,
      maneuverType: 'continue',
      modifier: 'straight',
      location: LatLng(45, -73),
      distanceFromStartM: 500,
      segmentDistanceM: 1200,
    );

    voice.onCoPilotCue(
      navStep: step,
      navDistanceM: 300,
      language: AppLanguage.korean,
      muted: false,
    );
    now = now.add(const Duration(seconds: 9));
    voice.onCoPilotCue(
      navStep: step,
      navDistanceM: 80,
      language: AppLanguage.korean,
      muted: false,
    );

    expect(spoken, ['300, 1.2킬로 직진']);
  });

  test('one kilometer is the exact straight briefing threshold', () {
    const shortStep = NavStep(
      sequence: 1,
      maneuverType: 'continue',
      modifier: 'straight',
      location: LatLng(45, -73),
      distanceFromStartM: 500,
      segmentDistanceM: 999,
    );
    const longStep = NavStep(
      sequence: 2,
      maneuverType: 'continue',
      modifier: 'straight',
      location: LatLng(45, -73),
      distanceFromStartM: 1500,
      segmentDistanceM: 1000,
    );

    voice.onCoPilotCue(
      navStep: shortStep,
      navDistanceM: 300,
      language: AppLanguage.korean,
      muted: false,
    );
    voice.onCoPilotCue(
      navStep: longStep,
      navDistanceM: 300,
      language: AppLanguage.korean,
      muted: false,
    );

    expect(spoken, ['300, 1킬로 직진']);
    expect(
      voice.buildCoPilotPhrase(
        language: AppLanguage.english,
        navStep: longStep,
        navDistanceM: 300,
      ),
      '300, straight for 1 kilometer',
    );
    expect(
      voice.buildCoPilotPhrase(
        language: AppLanguage.french,
        navStep: longStep,
        navDistanceM: 300,
      ),
      '300, tout droit sur 1 kilomètre',
    );
  });

  test(
    'long straight at the route start is announced without a zero prefix',
    () {
      voice.onCoPilotCue(
        navStep: const NavStep(
          sequence: 1,
          maneuverType: 'depart',
          modifier: 'straight',
          location: LatLng(45, -73),
          distanceFromStartM: 0,
          segmentDistanceM: 1200,
        ),
        navDistanceM: 0,
        language: AppLanguage.korean,
        muted: false,
      );

      expect(spoken, ['1.2킬로 직진']);
    },
  );

  test('speaks each navigation step only once', () {
    const step = NavStep(
      sequence: 1,
      maneuverType: 'fork',
      modifier: 'right',
      location: LatLng(45, -73),
      distanceFromStartM: 100,
      segmentDistanceM: 200,
    );

    voice.onCoPilotCue(
      navStep: step,
      navDistanceM: 300,
      language: AppLanguage.korean,
      muted: false,
    );
    now = now.add(const Duration(seconds: 9));
    voice.onCoPilotCue(
      navStep: step,
      navDistanceM: 80,
      language: AppLanguage.korean,
      muted: false,
    );

    expect(spoken, ['300, 우측 갈림길']);
  });

  test('rejoin navigation has a separate spoken-step namespace', () {
    const step = NavStep(
      sequence: 1,
      maneuverType: 'turn',
      modifier: 'right',
      location: LatLng(45, -73),
      distanceFromStartM: 100,
      segmentDistanceM: 200,
    );

    voice.onCoPilotCue(
      navStep: step,
      navDistanceM: 300,
      navNamespace: 'route',
      language: AppLanguage.korean,
      muted: false,
    );
    now = now.add(const Duration(seconds: 9));
    voice.onCoPilotCue(
      navStep: step,
      navDistanceM: 280,
      navNamespace: 'rejoin:1',
      language: AppLanguage.korean,
      muted: false,
    );

    expect(spoken, ['300, 우측 갈림길', '280, 우측 갈림길']);
  });

  test('finish omits a meaningless zero-distance prefix', () {
    final phrase = voice.buildCoPilotPhrase(
      language: AppLanguage.korean,
      navStep: const NavStep(
        sequence: 9,
        maneuverType: 'arrive',
        modifier: null,
        location: LatLng(45, -73),
        distanceFromStartM: 6400,
        segmentDistanceM: 0,
      ),
      navDistanceM: 0,
    );

    expect(phrase, '피니시');
  });

  test('off-route and back-on-route phrases use rally tone', () {
    voice.onRouteStatusChange(
      previous: DriveRouteStatus.onRoute,
      next: DriveRouteStatus.offRoute,
      language: AppLanguage.korean,
      muted: false,
      rejoinBearing: 90,
      currentHeading: 0,
    );
    now = now.add(const Duration(seconds: 9));
    voice.onRouteStatusChange(
      previous: DriveRouteStatus.offRoute,
      next: DriveRouteStatus.onRoute,
      language: AppLanguage.korean,
      muted: false,
    );

    expect(spoken, ['루트 이탈, 우측 재진입', '온 루트']);
  });

  test('off-route rejoin side is relative to the vehicle heading', () {
    voice.onRouteStatusChange(
      previous: DriveRouteStatus.onRoute,
      next: DriveRouteStatus.offRoute,
      language: AppLanguage.korean,
      muted: false,
      rejoinBearing: 0,
      currentHeading: 90,
    );

    expect(spoken, ['루트 이탈, 좌측 재진입']);
  });

  test('phrases avoid forbidden performance language in all languages', () {
    for (final language in AppLanguage.values) {
      final samples = [
        voice.buildPhrase(cue(), language: language),
        voice.buildPhrase(
          cue(curveCountAhead: 4, nextGapM: 150),
          language: language,
        ),
        voice.buildPhrase(
          cue(severity: 3),
          language: language,
          afterLongClear: true,
        ),
      ];
      for (final sample in samples) {
        for (final word in forbidden) {
          expect(sample, isNot(contains(word)), reason: '$language: $sample');
        }
      }
    }
  });

  test(
    'selects enhanced voice for the active locale and caches voices',
    () async {
      final fakeTts = _FakeVoiceTtsClient(
        voices: const [
          {'name': 'en-US Standard', 'locale': 'en-US', 'quality': 'default'},
          {'name': 'en-US Premium', 'locale': 'en-US', 'quality': 'premium'},
          {'name': 'ko-KR Enhanced', 'locale': 'ko-KR', 'quality': 'enhanced'},
        ],
      );
      final service = VoiceBriefingService(ttsFactory: () => fakeTts);

      service.onCue(cue(), language: AppLanguage.english, muted: false);
      await Future<void>.delayed(Duration.zero);

      expect(fakeTts.languages, ['en-US']);
      expect(fakeTts.speechRates.single, 0.5);
      expect(fakeTts.pitches.single, 1.0);
      expect(fakeTts.getVoicesCount, 1);
      expect(fakeTts.selectedVoices.single, {
        'name': 'en-US Premium',
        'locale': 'en-US',
      });
    },
  );

  test(
    'keeps default voice when no enhanced voice matches the locale',
    () async {
      final fakeTts = _FakeVoiceTtsClient(
        voices: const [
          {'name': 'en-US Standard', 'locale': 'en-US', 'quality': 'default'},
          {'name': 'ko-KR Premium', 'locale': 'ko-KR', 'quality': 'premium'},
        ],
      );
      final service = VoiceBriefingService(ttsFactory: () => fakeTts);

      service.onCue(cue(), language: AppLanguage.french, muted: false);
      await Future<void>.delayed(Duration.zero);

      expect(fakeTts.languages, ['fr-CA']);
      expect(fakeTts.selectedVoices, isEmpty);
      expect(fakeTts.spoken.single, '200, virage serré à droite');
    },
  );

  test(
    'announceStart stays silent because it has no driving information',
    () async {
      voice.announceStart(AppLanguage.korean, muted: false);
      voice.announceStart(AppLanguage.korean, muted: false);
      await Future<void>.delayed(Duration.zero);

      expect(spoken, isEmpty);
    },
  );

  test('announceStart stays silent while muted', () async {
    voice.announceStart(AppLanguage.korean, muted: true);
    await Future<void>.delayed(Duration.zero);

    expect(spoken, isEmpty);
  });

  test(
    'platform speech waits for the current phrase before starting next',
    () async {
      final firstSpeakGate = Completer<void>();
      final fakeTts = _FakeVoiceTtsClient(
        voices: const [],
        firstSpeakGate: firstSpeakGate,
      );
      final service = VoiceBriefingService(ttsFactory: () => fakeTts);

      service.onRouteStatusChange(
        previous: DriveRouteStatus.onRoute,
        next: DriveRouteStatus.offRoute,
        language: AppLanguage.korean,
        muted: false,
      );
      service.onRouteStatusChange(
        previous: DriveRouteStatus.offRoute,
        next: DriveRouteStatus.onRoute,
        language: AppLanguage.korean,
        muted: false,
      );
      await Future<void>.delayed(Duration.zero);

      expect(fakeTts.spoken, ['루트 이탈, 진행 방향 재진입']);

      firstSpeakGate.complete();
      await Future<void>.delayed(Duration.zero);

      expect(fakeTts.spoken, ['루트 이탈, 진행 방향 재진입', '온 루트']);
    },
  );
}

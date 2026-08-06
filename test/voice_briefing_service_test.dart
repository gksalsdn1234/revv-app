import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/core/app_language.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/services/drive_elevation_cue.dart';
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

  test(
    'debug candidate trace matches the selected phrase before TTS',
    () async {
      final delivered = <String>[];
      final debugLogs = <String>[];
      final service = VoiceBriefingService(
        speak: (text, _) async {
          expect(debugLogs, ['[REVV][VoiceBriefing][candidate] $text']);
          delivered.add(text);
        },
        debugLog: debugLogs.add,
      );

      service.onCue(
        cue(distanceM: 200),
        language: AppLanguage.korean,
        muted: false,
      );
      await Future<void>.delayed(Duration.zero);

      expect(delivered, ['200, 우측 급커브']);
      expect(debugLogs, [
        '[REVV][VoiceBriefing][candidate] ${delivered.single}',
      ]);
    },
  );

  test('debug candidate trace survives TTS failure', () async {
    final debugLogs = <String>[];
    final service = VoiceBriefingService(
      speak: (_, _) async => throw StateError('TTS unavailable'),
      debugLog: debugLogs.add,
    );

    service.onCue(cue(), language: AppLanguage.korean, muted: false);
    await Future<void>.delayed(Duration.zero);

    expect(debugLogs, ['[REVV][VoiceBriefing][candidate] 200, 우측 급커브']);
  });

  test('debug candidate trace excludes filtered speech paths', () async {
    final debugLogs = <String>[];
    final service = VoiceBriefingService(
      speak: (_, _) async {},
      clock: () => now,
      debugLog: debugLogs.add,
    );

    service.announceStart(AppLanguage.korean, muted: false);
    service.onCue(cue(), language: AppLanguage.korean, muted: true);
    service.onCue(cue(severity: 1), language: AppLanguage.korean, muted: false);
    service.onCue(
      cue(distanceM: 700),
      language: AppLanguage.korean,
      muted: false,
    );
    expect(debugLogs, isEmpty);

    service.onCue(
      cue(distanceM: 100),
      language: AppLanguage.korean,
      muted: false,
    );
    service.onCue(
      cue(distanceM: 100),
      language: AppLanguage.korean,
      muted: false,
    );
    service.onCue(
      cue(distanceM: 300),
      language: AppLanguage.korean,
      muted: false,
    );
    await Future<void>.delayed(Duration.zero);

    expect(debugLogs, ['[REVV][VoiceBriefing][candidate] 100, 우측 급커브']);
  });

  test('finds a meaningful upcoming climb from the route profile', () {
    final elevation = nextDriveElevationCue(
      elevationProfile: const [100, 100, 145],
      routeDistanceKm: 1,
      routeProgress: 0.1,
    );

    expect(elevation, isNotNull);
    expect(elevation!.trend, DriveElevationTrend.uphill);
    expect(elevation.changeM, 45);
    expect(elevation.distanceM, 400);
    expect(elevation.stageId, 'uphill:1:2');
  });

  test('finds a descent already in progress', () {
    final elevation = nextDriveElevationCue(
      elevationProfile: const [180, 130, 130],
      routeDistanceKm: 1,
      routeProgress: 0.2,
    );

    expect(elevation, isNotNull);
    expect(elevation!.trend, DriveElevationTrend.downhill);
    expect(elevation.changeM, 30);
    expect(elevation.distanceM, 0);
    expect(elevation.stageId, 'downhill:0:2');
  });

  test('ignores small, gentle, and malformed elevation profiles', () {
    expect(
      nextDriveElevationCue(
        elevationProfile: const [100, 110, 105, 115],
        routeDistanceKm: 1,
        routeProgress: 0,
      ),
      isNull,
    );
    expect(
      nextDriveElevationCue(
        elevationProfile: const [100, 140],
        routeDistanceKm: 3,
        routeProgress: 0,
      ),
      isNull,
    );
    expect(
      nextDriveElevationCue(
        elevationProfile: const [100, double.nan],
        routeDistanceKm: 1,
        routeProgress: 0,
      ),
      isNull,
    );
  });

  test('finds only an evidence-backed local crest', () {
    final crest = nextDriveElevationCue(
      elevationProfile: const [100, 150, 100],
      routeDistanceKm: 1,
      routeProgress: 0.2,
    );

    expect(crest, isNotNull);
    expect(crest!.isCrest, isTrue);
    expect(crest.distanceM, 300);
    expect(crest.changeM, 50);
    expect(crest.followingChangeM, 50);
    expect(crest.stageId, 'crest:1');
    expect(
      voice.buildElevationPhrase(crest, language: AppLanguage.english),
      '300, crest, 50 up, 50 down',
    );
    expect(
      voice.buildElevationPhrase(crest, language: AppLanguage.korean),
      '300, 크레스트, 상승 50, 하강 50',
    );
    expect(
      voice.buildElevationPhrase(crest, language: AppLanguage.french),
      '300, crête, montée 50, descente 50',
    );

    final monotonic = nextDriveElevationCue(
      elevationProfile: const [100, 150, 200],
      routeDistanceKm: 1,
      routeProgress: 0,
    );
    expect(monotonic?.isCrest ?? false, isFalse);
  });

  test('curve call wins first, then elevation speaks once after cooldown', () {
    const elevation = DriveElevationCue(
      trend: DriveElevationTrend.uphill,
      changeM: 44,
      distanceM: 210,
      stageId: 'uphill:2:6',
    );

    voice.onCue(cue(), language: AppLanguage.korean, muted: false);
    voice.onElevationCue(elevation, language: AppLanguage.korean, muted: false);
    expect(spoken, ['200, 우측 급커브']);

    now = now.add(const Duration(seconds: 6));
    voice.onElevationCue(elevation, language: AppLanguage.korean, muted: false);
    now = now.add(const Duration(seconds: 6));
    voice.onElevationCue(elevation, language: AppLanguage.korean, muted: false);

    expect(spoken, ['200, 우측 급커브', '210, 오르막, 상승 40미터']);
  });

  test('a merged grade is consumed and does not speak twice', () {
    const climb = DriveElevationCue(
      trend: DriveElevationTrend.uphill,
      changeM: 44,
      distanceM: 210,
      stageId: 'uphill:2:6',
    );

    voice.onCoPilotCue(
      curveCue: cue(distanceM: 200),
      elevationCue: climb,
      language: AppLanguage.english,
      muted: false,
    );
    now = now.add(const Duration(seconds: 6));
    voice.onElevationCue(climb, language: AppLanguage.english, muted: false);

    expect(spoken, ['200, sharp right, climb 40']);
  });

  test('elevation phrases are short and localized', () {
    const descent = DriveElevationCue(
      trend: DriveElevationTrend.downhill,
      changeM: 53,
      distanceM: 0,
      stageId: 'downhill:3:8',
    );

    expect(
      voice.buildElevationPhrase(descent, language: AppLanguage.english),
      'descent, 50 meters',
    );
    expect(
      voice.buildElevationPhrase(descent, language: AppLanguage.french),
      'descente, 50 mètres',
    );
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
    expect(spoken.single, '200, 우측 급커브, 연속 커브');
    expect(spoken.single, isNot(contains('좌우')));
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

    expect(spoken.single, '200, 우측 커브, 연속 커브');
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

    expect(spoken.single, '200, 우측 커브, 연속 커브');
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
      '200, right, bends continue',
    );
    expect(
      voice.buildPhrase(mediumPair, language: AppLanguage.french),
      '200, droite, virages enchaînés',
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

  test('cooldown opens at exactly five seconds', () {
    voice.onCue(
      cue(distanceM: 150),
      language: AppLanguage.english,
      muted: false,
    );
    now = now.add(const Duration(seconds: 5));
    voice.onCue(
      cue(distanceM: 300, direction: 'left'),
      language: AppLanguage.english,
      muted: false,
    );

    expect(spoken, ['150, sharp right', '300, sharp left']);
  });

  test('a navigation call does not falsely dedupe the next curve', () {
    voice.onCoPilotCue(
      navStep: const NavStep(
        sequence: 1,
        maneuverType: 'turn',
        modifier: 'left',
        location: LatLng(45, -73),
        distanceFromStartM: 200,
        segmentDistanceM: 400,
      ),
      navDistanceM: 200,
      language: AppLanguage.english,
      muted: false,
    );
    now = now.add(const Duration(seconds: 6));
    voice.onCue(
      cue(distanceM: 100),
      language: AppLanguage.english,
      muted: false,
    );

    expect(spoken, ['200, left', '100, sharp right']);
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

  test('does not merge TBT and curve events at different positions', () {
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

    expect(phrase, '300, 우측 유지');
    expect(phrase, isNot(contains('미터 앞')));
    expect(phrase, isNot(contains('하세요')));
  });

  test('merges only colocated curve and maneuver into one compact call', () {
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
      navDistanceM: 180,
      curveCue: cue(distanceM: 120, direction: '좌측'),
      preferCurve: true,
    );

    expect(phrase, '120, 좌측 급커브, 우측 유지');
  });

  test('crest can be the single secondary fact beside a curve', () {
    const crest = DriveElevationCue(
      trend: DriveElevationTrend.uphill,
      feature: DriveElevationFeature.crest,
      changeM: 50,
      followingChangeM: 40,
      distanceM: 150,
      stageId: 'crest:4',
    );
    final phrase = voice.buildCoPilotPhrase(
      language: AppLanguage.english,
      curveCue: cue(distanceM: 120, direction: 'left'),
      elevationCue: crest,
      preferCurve: true,
    );

    expect(phrase, '120, sharp left, crest');
  });

  test('every severity gets its own call', () {
    // The regression this pins: severity used to reach the voice only through
    // intensityLabel, a translated display string. When that wording was
    // renamed the match silently stopped and all four severities collapsed
    // onto the same "turn right".
    final spoken = <int, String>{
      for (final severity in [0, 1, 2, 3])
        severity: voice.buildCoPilotPhrase(
          language: AppLanguage.english,
          curveCue: cue(
            distanceM: 200,
            direction: 'right',
            severity: severity,
          ),
          preferCurve: true,
        ),
    };

    expect(spoken.values.toSet(), hasLength(4), reason: spoken.toString());
    expect(spoken[3], contains('very sharp'));
    expect(spoken[2], contains('sharp right'));
    expect(spoken[0], contains('gentle'));
  });

  test('the call ignores the display wording and follows severity', () {
    // route_drive_cue labels a severity-2 curve "Sharp" today and called it
    // "Tight" before. Neither word may decide what gets spoken.
    final phrases = ['Sharp', 'Tight', '급커브', 'anything at all'].map(
      (label) => voice.buildCoPilotPhrase(
        language: AppLanguage.english,
        curveCue: cue(
          distanceM: 200,
          direction: 'right',
          intensity: label,
          severity: 2,
        ),
        preferCurve: true,
      ),
    );

    expect(phrases.toSet(), hasLength(1));
    expect(phrases.first, contains('sharp right'));
  });

  test('a merged call does not say the same side twice', () {
    // Observed on a real drive: the curve called "turn right" and the colocated
    // maneuver called "right", so the phrase came out "210, turn right, right".
    // The second word carries nothing the first has not already said.
    final phrase = voice.buildCoPilotPhrase(
      language: AppLanguage.english,
      navStep: const NavStep(
        sequence: 1,
        maneuverType: 'turn',
        modifier: 'right',
        location: LatLng(45, -73),
        distanceFromStartM: 100,
        segmentDistanceM: 200,
      ),
      navDistanceM: 210,
      curveCue: cue(distanceM: 210, direction: 'right', curveCountAhead: 3),
      preferCurve: true,
    );

    expect(phrase, startsWith('210, sharp right'));
    expect(phrase, isNot(contains('right, right')));
  });

  test('a merged curve still speaks when it adds intensity', () {
    final phrase = voice.buildCoPilotPhrase(
      language: AppLanguage.english,
      navStep: const NavStep(
        sequence: 1,
        maneuverType: 'turn',
        modifier: 'right',
        location: LatLng(45, -73),
        distanceFromStartM: 100,
        segmentDistanceM: 200,
      ),
      navDistanceM: 210,
      curveCue: cue(distanceM: 210, direction: 'right', intensity: 'tight'),
    );

    expect(phrase, contains('sharp right'));
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

    expect(phrase, '120, 좌측 급커브');
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
      navDistanceM: 200,
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

    expect(spoken, ['200, 우측 유지, 좌측 급커브']);
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

    expect(spoken.single, '220, 우측 급커브, 연속 커브');
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

    expect(spoken.single, '220, 우측 급커브, 연속 커브');
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

    expect(spoken, ['300, 직진 1.2킬로']);
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

    expect(spoken, ['300, 직진 1킬로']);
    expect(
      voice.buildCoPilotPhrase(
        language: AppLanguage.english,
        navStep: longStep,
        navDistanceM: 300,
      ),
      '300, straight 1 kilometer',
    );
    expect(
      voice.buildCoPilotPhrase(
        language: AppLanguage.french,
        navStep: longStep,
        navDistanceM: 300,
      ),
      '300, tout droit 1 kilomètre',
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

      expect(spoken, ['직진 1.2킬로']);
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

    expect(spoken, ['300, 우측 유지']);
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

    expect(spoken, ['300, 우측', '280, 우측']);
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

  test('completed frame speaks finish exactly once at zero distance', () {
    const finish = NavStep(
      sequence: 9,
      maneuverType: 'arrive',
      modifier: null,
      location: LatLng(45, -73),
      distanceFromStartM: 6400,
      segmentDistanceM: 0,
    );
    final frame = DriveCoPilotFrame(
      previousStatus: DriveRouteStatus.onRoute,
      nextStatus: DriveRouteStatus.completed,
      navStep: finish,
      navDistanceM: 0,
      language: AppLanguage.korean,
      muted: false,
    );

    voice.onDriveFrame(frame);
    now = now.add(const Duration(seconds: 9));
    voice.onDriveFrame(frame);

    expect(spoken, ['피니시']);
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

  test('route transition preempts every lower-priority frame event', () {
    const climb = DriveElevationCue(
      trend: DriveElevationTrend.uphill,
      changeM: 40,
      distanceM: 120,
      stageId: 'uphill:1:2',
    );
    voice.onDriveFrame(
      DriveCoPilotFrame(
        previousStatus: DriveRouteStatus.onRoute,
        nextStatus: DriveRouteStatus.offRoute,
        navStep: const NavStep(
          sequence: 1,
          maneuverType: 'turn',
          modifier: 'left',
          location: LatLng(45, -73),
          distanceFromStartM: 100,
          segmentDistanceM: 200,
        ),
        navDistanceM: 100,
        curveCue: cue(distanceM: 100),
        elevationCue: climb,
        preferCurve: true,
        language: AppLanguage.english,
        muted: false,
      ),
    );

    expect(spoken, ['off route, rejoin ahead']);
  });

  test('one-sample curve dropout does not repeat the same curve', () {
    voice.onCue(
      cue(distanceM: 200),
      language: AppLanguage.english,
      muted: false,
    );
    now = now.add(const Duration(seconds: 6));
    voice.onCue(null, language: AppLanguage.english, muted: false);
    now = now.add(const Duration(seconds: 1));
    voice.onCue(
      cue(distanceM: 130),
      language: AppLanguage.english,
      muted: false,
    );

    expect(spoken, ['200, sharp right']);
  });

  test('navigation-only clear gap rearms a later physical curve', () {
    const navigation = NavStep(
      sequence: 3,
      maneuverType: 'fork',
      modifier: 'left',
      location: LatLng(45, -73),
      distanceFromStartM: 800,
      segmentDistanceM: 200,
    );
    voice.onCue(
      cue(distanceM: 200),
      language: AppLanguage.english,
      muted: false,
    );
    now = now.add(const Duration(seconds: 6));
    voice.onCoPilotCue(
      navStep: navigation,
      navDistanceM: 300,
      language: AppLanguage.english,
      muted: false,
    );
    now = now.add(const Duration(seconds: 4));
    voice.onCoPilotCue(
      navStep: navigation,
      navDistanceM: 280,
      language: AppLanguage.english,
      muted: false,
    );
    now = now.add(const Duration(seconds: 2));
    voice.onCue(
      cue(distanceM: 250, direction: 'left'),
      language: AppLanguage.english,
      muted: false,
    );

    expect(spoken, ['200, sharp right', '300, keep left', '250, sharp left']);
  });

  test('unknown curve labels never invent a right-hand bend', () {
    final phrase = voice.buildPhrase(
      cue(direction: 'unknown', intensity: 'unknown'),
      language: AppLanguage.english,
    );

    // The grade still comes through — severity knows the corner is sharp even
    // when the direction cannot be read. What must never appear is a side.
    expect(phrase, '200, sharp turn');
    expect(phrase, isNot(contains('right')));
  });

  test('unproven alternation wording is absent in every language', () {
    for (final language in AppLanguage.values) {
      final phrase = voice.buildPhrase(
        cue(curveCountAhead: 11, nextGapM: 70),
        language: language,
      );
      expect(phrase.toLowerCase(), isNot(contains('alternat')));
      expect(phrase, isNot(contains('좌우')));
    }
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
      expect(fakeTts.spoken.single, '200, droite serrée');
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

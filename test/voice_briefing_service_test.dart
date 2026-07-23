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
  int cornerId = 1,
  String? nextDirection,
  String? nextIntensity,
  int? nextCornerId,
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
    cornerId: cornerId,
    nextDirectionLabel: nextDirection,
    nextIntensityLabel: nextIntensity,
    nextCornerId: nextCornerId,
  );
}

class _FakeVoiceTtsClient implements VoiceTtsClient {
  _FakeVoiceTtsClient({required this.voices});

  final Object? voices;
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
  Future<void> speak(String text) async => spoken.add(text);

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

  test('speaks a corner once, at the speed-scaled lead point', () {
    // 60km/h → 리드 약 117m. 300/200m은 아직 이르고 90m에서 부른다.
    for (final distanceM in [300.0, 200.0, 90.0, 70.0]) {
      voice.onCoPilotCue(
        curveCue: cue(distanceM: distanceM),
        speedKmh: 60,
        language: AppLanguage.korean,
        muted: false,
      );
    }

    expect(spoken, hasLength(1));
    expect(spoken.first, '90, 우 타이트');
  });

  test('lead point scales with speed — faster means earlier', () {
    voice.onCoPilotCue(
      curveCue: cue(distanceM: 200),
      speedKmh: 110,
      language: AppLanguage.korean,
      muted: false,
    );
    expect(spoken.single, '200, 우 타이트');
  });

  test('stays silent when muted or when the cue is not a corner', () {
    voice.onCoPilotCue(
      curveCue: cue(distanceM: 100),
      speedKmh: 60,
      language: AppLanguage.korean,
      muted: true,
    );
    voice.onCoPilotCue(
      curveCue: cue(distanceM: 100, severity: 0, cornerId: 2),
      speedKmh: 60,
      language: AppLanguage.korean,
      muted: false,
    );
    voice.onCoPilotCue(
      curveCue: cue(distanceM: 100, curveCountAhead: 0, cornerId: 3),
      speedKmh: 60,
      language: AppLanguage.korean,
      muted: false,
    );
    expect(spoken, isEmpty);
  });

  test('medium corners are called too — not only tight and hairpin', () {
    voice.onCoPilotCue(
      curveCue: cue(distanceM: 100, severity: 1, intensity: '중간'),
      speedKmh: 60,
      language: AppLanguage.korean,
      muted: false,
    );
    expect(spoken.single, '100, 우 중간');
  });

  test('drops a corner that is already too close to call', () {
    voice.onCoPilotCue(
      curveCue: cue(distanceM: 30),
      speedKmh: 60,
      language: AppLanguage.korean,
      muted: false,
    );
    expect(spoken, isEmpty);
  });

  test('combo pattern announces the chain', () {
    voice.onCoPilotCue(
      curveCue: cue(distanceM: 100, curveCountAhead: 4, nextGapM: 150),
      speedKmh: 60,
      language: AppLanguage.korean,
      muted: false,
    );
    expect(spoken.single, contains('연속'));
    expect(spoken.single, contains('4개'));
  });

  test('linked corner is read in the same breath and not repeated', () {
    voice.onCoPilotCue(
      curveCue: cue(
        distanceM: 100,
        nextGapM: 90,
        nextDirection: '좌측',
        nextIntensity: '중간',
        nextCornerId: 2,
      ),
      speedKmh: 60,
      language: AppLanguage.korean,
      muted: false,
    );
    expect(spoken.single, '100, 우 타이트 — 짧게 좌 중간');

    // 링크로 이미 읽은 코너가 다음 큐로 올라와도 다시 부르지 않는다.
    now = now.add(const Duration(seconds: 10));
    voice.onCoPilotCue(
      curveCue: cue(
        distanceM: 100,
        cornerId: 2,
        direction: '좌측',
        intensity: '중간',
      ),
      speedKmh: 60,
      language: AppLanguage.korean,
      muted: false,
    );
    expect(spoken, hasLength(1));
  });

  test('minimum gap suppresses a second callout, then releases it', () {
    voice.onCoPilotCue(
      curveCue: cue(distanceM: 100),
      speedKmh: 60,
      language: AppLanguage.korean,
      muted: false,
    );
    now = now.add(const Duration(seconds: 3));
    voice.onCoPilotCue(
      curveCue: cue(distanceM: 110, cornerId: 2),
      speedKmh: 60,
      language: AppLanguage.korean,
      muted: false,
    );
    expect(spoken, hasLength(1));

    // 간격에 막힌 콜은 버려지지 않는다 — 다음 샘플에서 다시 나온다.
    now = now.add(const Duration(seconds: 2));
    voice.onCoPilotCue(
      curveCue: cue(distanceM: 100, cornerId: 2),
      speedKmh: 60,
      language: AppLanguage.korean,
      muted: false,
    );
    expect(spoken, hasLength(2));
  });

  test('calls every corner through a continuous curvy section', () {
    // 연속 코너 구간: 큐가 한 번도 사라지지 않고 코너만 바뀐다.
    for (var i = 0; i < 5; i++) {
      voice.onCoPilotCue(
        curveCue: cue(
          distanceM: 100,
          cornerId: 100 + i,
          curveCountAhead: 5 - i,
        ),
        speedKmh: 60,
        language: AppLanguage.korean,
        muted: false,
      );
      now = now.add(const Duration(seconds: 5));
    }
    expect(spoken, hasLength(5));
  });

  test('a distant nav step no longer silences corner briefings', () {
    // 교차로 없는 산길: 다음 분기가 6km 앞이어도 코너는 읽어야 한다.
    voice.onCoPilotCue(
      navStep: const NavStep(
        sequence: 1,
        maneuverType: 'arrive',
        modifier: null,
        location: LatLng(45, -73),
        distanceFromStartM: 6000,
      ),
      navDistanceM: 6000,
      curveCue: cue(distanceM: 100),
      speedKmh: 60,
      language: AppLanguage.korean,
      muted: false,
    );
    expect(spoken.single, '100, 우 타이트');
  });

  test('long clear gap adds the flow-ending prefix', () {
    // 첫 큐 관측 (발화 없이 창 밖)
    voice.onCoPilotCue(
      curveCue: cue(distanceM: 700),
      speedKmh: 60,
      language: AppLanguage.korean,
      muted: false,
    );
    // 20초 이상 큐 없음 → 긴 흐름 구간
    now = now.add(const Duration(seconds: 25));
    voice.onCoPilotCue(
      curveCue: cue(distanceM: 100),
      speedKmh: 60,
      language: AppLanguage.korean,
      muted: false,
    );
    expect(spoken.single, '100, 긴 흐름 구간 — 우 타이트');
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
      ),
      navDistanceM: 300,
      curveCue: cue(distanceM: 120, direction: '좌측'),
    );

    expect(phrase, '300, 우측 갈림길 — 바로 좌 타이트');
    expect(phrase, isNot(contains('미터 앞')));
    expect(phrase, isNot(contains('하세요')));
  });

  test('speaks 300m and 80m stages for the same nav step', () {
    const step = NavStep(
      sequence: 1,
      maneuverType: 'fork',
      modifier: 'right',
      location: LatLng(45, -73),
      distanceFromStartM: 100,
    );

    voice.onCoPilotCue(
      navStep: step,
      navDistanceM: 300,
      speedKmh: 60,
      language: AppLanguage.korean,
      muted: false,
    );
    now = now.add(const Duration(seconds: 9));
    voice.onCoPilotCue(
      navStep: step,
      navDistanceM: 80,
      speedKmh: 60,
      language: AppLanguage.korean,
      muted: false,
    );

    expect(spoken, ['300, 우측 갈림길', '80, 우측 갈림길']);
  });

  test('off-route and back-on-route phrases use rally tone', () {
    voice.onRouteStatusChange(
      previous: DriveRouteStatus.onRoute,
      next: DriveRouteStatus.offRoute,
      language: AppLanguage.korean,
      muted: false,
      rejoinBearing: 90,
    );
    now = now.add(const Duration(seconds: 9));
    voice.onRouteStatusChange(
      previous: DriveRouteStatus.offRoute,
      next: DriveRouteStatus.onRoute,
      language: AppLanguage.korean,
      muted: false,
    );

    expect(spoken, ['루트 이탈 — 우측에서 재진입', '온 루트']);
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
        // 연결 콜("짧게 좌 중간")도 같은 안전 규칙을 지켜야 한다.
        voice.buildPhrase(
          cue(
            nextGapM: 90,
            nextDirection: '좌측',
            nextIntensity: '중간',
            nextCornerId: 2,
          ),
          language: language,
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

      service.announceStart(AppLanguage.english, muted: false);
      await Future<void>.delayed(Duration.zero);
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

      service.announceStart(AppLanguage.french, muted: false);
      await Future<void>.delayed(Duration.zero);

      expect(fakeTts.languages, ['fr-CA']);
      expect(fakeTts.selectedVoices, isEmpty);
      expect(
        fakeTts.spoken.single,
        'Le briefing virages est actif. Bonne route.',
      );
    },
  );

  test('announceStart speaks once and then no-ops', () async {
    voice.announceStart(AppLanguage.korean, muted: false);
    voice.announceStart(AppLanguage.korean, muted: false);
    await Future<void>.delayed(Duration.zero);

    expect(spoken, ['코너 브리핑을 시작해요. 좋은 드라이브 되세요.']);
  });

  test('announceStart stays silent while muted', () async {
    voice.announceStart(AppLanguage.korean, muted: true);
    await Future<void>.delayed(Duration.zero);

    expect(spoken, isEmpty);
  });
}

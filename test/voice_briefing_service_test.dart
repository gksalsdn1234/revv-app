import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/core/app_language.dart';
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

  test('speaks a tight curve once inside the window', () {
    voice.onCue(cue(distanceM: 300), language: AppLanguage.korean, muted: false);
    voice.onCue(cue(distanceM: 200), language: AppLanguage.korean, muted: false);
    voice.onCue(cue(distanceM: 90), language: AppLanguage.korean, muted: false);

    expect(spoken, hasLength(1));
    expect(spoken.first, contains('우측 타이트'));
    expect(spoken.first, contains('여유 있게 진입'));
  });

  test('stays silent when muted or severity is low', () {
    voice.onCue(cue(), language: AppLanguage.korean, muted: true);
    voice.onCue(cue(severity: 1), language: AppLanguage.korean, muted: false);
    voice.onCue(
      cue(severity: 2, curveCountAhead: 0), // 이탈/상태 큐
      language: AppLanguage.korean,
      muted: false,
    );
    expect(spoken, isEmpty);
  });

  test('ignores curves outside the speaking window', () {
    voice.onCue(cue(distanceM: 700), language: AppLanguage.korean, muted: false);
    voice.onCue(cue(distanceM: 30), language: AppLanguage.korean, muted: false);
    expect(spoken, isEmpty);
  });

  test('combo pattern announces the chain', () {
    voice.onCue(
      cue(curveCountAhead: 4, nextGapM: 150),
      language: AppLanguage.korean,
      muted: false,
    );
    expect(spoken.single, contains('연속'));
    expect(spoken.single, contains('4개'));
  });

  test('hairpin gets the prepare-early phrasing', () {
    voice.onCue(
      cue(severity: 3, intensity: '헤어핀'),
      language: AppLanguage.korean,
      muted: false,
    );
    expect(spoken.single, contains('헤어핀'));
    expect(spoken.single, contains('미리 준비'));
  });

  test('cooldown suppresses a second callout within 8 seconds', () {
    voice.onCue(cue(distanceM: 200), language: AppLanguage.korean, muted: false);
    // 커브 통과(큐 소멸) 후 곧바로 새 커브 — 쿨다운에 걸림
    voice.onCue(null, language: AppLanguage.korean, muted: false);
    now = now.add(const Duration(seconds: 4));
    voice.onCue(cue(distanceM: 250), language: AppLanguage.korean, muted: false);
    expect(spoken, hasLength(1));

    now = now.add(const Duration(seconds: 5));
    voice.onCue(cue(distanceM: 240), language: AppLanguage.korean, muted: false);
    expect(spoken, hasLength(2));
  });

  test('re-arms for a new farther curve after passing the spoken one', () {
    voice.onCue(cue(distanceM: 150), language: AppLanguage.korean, muted: false);
    now = now.add(const Duration(seconds: 10));
    // 발화한 커브(150m)보다 충분히 먼 새 커브
    voice.onCue(cue(distanceM: 310), language: AppLanguage.korean, muted: false);
    expect(spoken, hasLength(2));
  });

  test('long clear gap adds the flow-ending prefix', () {
    // 첫 큐 관측 (발화 없이 창 밖)
    voice.onCue(cue(distanceM: 700), language: AppLanguage.korean, muted: false);
    // 20초 이상 큐 없음 → 긴 흐름 구간
    now = now.add(const Duration(seconds: 25));
    voice.onCue(cue(distanceM: 300), language: AppLanguage.korean, muted: false);
    expect(spoken.single, startsWith('긴 흐름 구간이 끝나요.'));
  });

  test('phrases avoid forbidden performance language in all languages', () {
    for (final language in AppLanguage.values) {
      final samples = [
        voice.buildPhrase(cue(), language: language),
        voice.buildPhrase(
          cue(curveCountAhead: 4, nextGapM: 150),
          language: language,
        ),
        voice.buildPhrase(cue(severity: 3), language: language, afterLongClear: true),
      ];
      for (final sample in samples) {
        for (final word in forbidden) {
          expect(sample, isNot(contains(word)), reason: '$language: $sample');
        }
      }
    }
  });
}

import 'package:flutter_tts/flutter_tts.dart';

import '../core/app_language.dart';
import '../ui/route_drive_cue.dart';
import 'audio_session.dart';

/// TTS 발화 시임 — 테스트에서 fake 주입.
typedef VoiceSpeak = Future<void> Function(String text, AppLanguage language);

/// 주행 중 음성 코너 브리핑 (코파일럿 1호).
///
/// 원칙: 말을 아낀다. 놀랄 코너(타이트 이상)만, 커브당 1회, 콜아웃 간
/// 최소 [cooldown]. 음악은 멈추지 않고 위에 얹는다(iOS duckOthers).
/// TTS 실패는 조용히 무시한다 — 브리핑은 보조 수단이고 앱은 죽지 않는다.
class VoiceBriefingService {
  VoiceBriefingService({VoiceSpeak? speak, DateTime Function()? clock})
    : _speakOverride = speak,
      _clock = clock ?? DateTime.now;

  static const cooldown = Duration(seconds: 8);

  /// 이 창 안에 들어온 커브만 읽는다 (너무 멀면 소음, 너무 가까우면 뒷북).
  static const speakWindowMinM = 50.0;
  static const speakWindowMaxM = 320.0;

  /// 이 시간 이상 커브 큐가 없다가 급코너가 나타나면 "긴 흐름 구간 끝" 패턴.
  static const longClearGap = Duration(seconds: 20);

  final VoiceSpeak? _speakOverride;
  final DateTime Function() _clock;

  FlutterTts? _tts;
  AppLanguage? _ttsLanguage;
  DateTime? _lastSpokenAt;
  double? _spokenDistanceM;
  DateTime? _lastCueSeenAt;

  /// 주행 샘플마다 호출. 조건이 맞을 때만 발화한다.
  void onCue(DriveCurveCue? cue, {required AppLanguage language, required bool muted}) {
    final now = _clock();
    if (cue == null || cue.severity <= 0) {
      // 큐가 사라짐 = 커브 통과/흐름 구간. 다음 커브를 위해 재무장.
      _spokenDistanceM = null;
      return;
    }

    // 첫 큐(세션 시작)는 "긴 흐름 뒤"로 치지 않는다 — 관측 이력이 있어야 판정
    final lastSeen = _lastCueSeenAt;
    final hadLongClear =
        lastSeen != null && now.difference(lastSeen) >= longClearGap;
    _lastCueSeenAt = now;

    if (muted) return;
    if (cue.severity < 2) return; // 완만/중간은 침묵 — 놀랄 코너만
    if (cue.curveCountAhead < 1) return; // 이탈/시작/완료 큐는 코너가 아님
    if (cue.distanceM < speakWindowMinM || cue.distanceM > speakWindowMaxM) {
      return;
    }

    // 같은 커브 접근 중 재발화 방지: 발화 후 거리가 크게 늘어나야(=새 커브) 재무장
    final spokenAt = _spokenDistanceM;
    if (spokenAt != null && cue.distanceM <= spokenAt + 120) return;

    final last = _lastSpokenAt;
    if (last != null && now.difference(last) < cooldown) return;

    final phrase = buildPhrase(cue, language: language, afterLongClear: hadLongClear);
    _lastSpokenAt = now;
    _spokenDistanceM = cue.distanceM;
    _speak(phrase, language);
  }

  /// 큐 → 안내 문장. 패턴: ①긴 흐름 뒤 급코너 ②연속 콤보 ③단일 급코너.
  /// 안전 언어: 거리·방향·성격 + "여유 있게 진입" 톤. 속도 지시 금지.
  String buildPhrase(
    DriveCurveCue cue, {
    required AppLanguage language,
    bool afterLongClear = false,
  }) {
    final distance = _roundedDistance(cue.distanceM, language);
    final corner = '${cue.directionLabel} ${cue.intensityLabel}';

    final isCombo = cue.curveCountAhead >= 3 && (cue.nextGapM ?? 999) <= 280;
    final body = isCombo
        ? _t(
            language,
            ko: '$distance 앞 $corner, 이어서 코너 ${cue.curveCountAhead}개가 연속돼요.',
            en: '$corner in $distance, then ${cue.curveCountAhead} corners in a row.',
            fr: '$corner dans $distance, puis ${cue.curveCountAhead} virages enchaînés.',
          )
        : cue.severity >= 3
        ? _t(
            language,
            ko: '$distance 앞 $corner이에요. 미리 준비하세요.',
            en: '$corner in $distance. Get set early.',
            fr: '$corner dans $distance. Préparez-vous tôt.',
          )
        : _t(
            language,
            ko: '$distance 앞 $corner 커브예요. 여유 있게 진입하세요.',
            en: '$corner curve in $distance. Ease into it.',
            fr: 'Virage $corner dans $distance. Entrez en souplesse.',
          );

    if (afterLongClear) {
      final prefix = _t(
        language,
        ko: '긴 흐름 구간이 끝나요. ',
        en: 'Long flow section ending. ',
        fr: 'Fin de la section fluide. ',
      );
      return '$prefix$body';
    }
    return body;
  }

  // 재진입 가드는 쿨다운(8초)이 담당한다 — 별도 플래그는 두지 않는다
  Future<void> _speak(String phrase, AppLanguage language) async {
    try {
      final override = _speakOverride;
      if (override != null) {
        await override(phrase, language);
        return;
      }
      final tts = await _ensureTts(language);
      if (tts == null) return;
      await tts.speak(phrase);
    } catch (_) {
      // TTS 실패는 조용히 — 시각 배너가 항상 있다
    }
  }

  Future<FlutterTts?> _ensureTts(AppLanguage language) async {
    try {
      var tts = _tts;
      if (tts == null) {
        tts = FlutterTts();
        await configureMusicDuckingAudioSession(
          setIosAudioCategory: tts.setIosAudioCategory,
        );
        await tts.setSpeechRate(0.5);
        _tts = tts;
      }
      if (_ttsLanguage != language) {
        await tts.setLanguage(switch (language) {
          AppLanguage.korean => 'ko-KR',
          AppLanguage.french => 'fr-CA',
          _ => 'en-US',
        });
        _ttsLanguage = language;
      }
      return tts;
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    try {
      _tts?.stop();
    } catch (_) {}
    _tts = null;
  }

  String _roundedDistance(double meters, AppLanguage language) {
    if (meters >= 950) {
      final km = (meters / 1000).toStringAsFixed(1);
      return _t(language, ko: '약 $km킬로미터', en: 'about $km kilometers', fr: 'environ $km kilomètres');
    }
    final rounded = ((meters / 50).round() * 50).clamp(50, 900);
    return _t(language, ko: '약 $rounded미터', en: 'about $rounded meters', fr: 'environ $rounded mètres');
  }

  String _t(AppLanguage language, {required String ko, required String en, required String fr}) {
    return switch (language) {
      AppLanguage.korean => ko,
      AppLanguage.french => fr,
      _ => en,
    };
  }
}

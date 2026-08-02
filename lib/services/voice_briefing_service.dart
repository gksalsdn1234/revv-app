import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../core/app_language.dart';
import '../ui/route_drive_cue.dart';
import 'audio_session.dart';
import 'route_turn_service.dart';

/// TTS 발화 시임 — 테스트에서 fake 주입.
typedef VoiceSpeak = Future<void> Function(String text, AppLanguage language);
typedef VoiceTtsFactory = VoiceTtsClient Function();

/// 실제 TTS 플러그인 시임 — 테스트에서 fake voice 목록/선택을 검증한다.
abstract class VoiceTtsClient {
  Future<void> configureAudioSession();
  Future<void> setSpeechRate(double rate);
  Future<void> setPitch(double pitch);
  Future<void> setLanguage(String language);
  Future<Object?> getVoices();
  Future<void> setVoice(Map<String, String> voice);
  Future<void> speak(String text);
  Future<void> stop();
}

class _FlutterVoiceTtsClient implements VoiceTtsClient {
  _FlutterVoiceTtsClient() : _tts = FlutterTts();

  final FlutterTts _tts;

  @override
  Future<void> configureAudioSession() => configureMusicDuckingAudioSession(
    setIosAudioCategory: _tts.setIosAudioCategory,
  );

  @override
  Future<void> setSpeechRate(double rate) => _tts.setSpeechRate(rate);

  @override
  Future<void> setPitch(double pitch) => _tts.setPitch(pitch);

  @override
  Future<void> setLanguage(String language) => _tts.setLanguage(language);

  @override
  Future<Object?> getVoices() async => _tts.getVoices;

  @override
  Future<void> setVoice(Map<String, String> voice) => _tts.setVoice(voice);

  @override
  Future<void> speak(String text) => _tts.speak(text);

  @override
  Future<void> stop() => _tts.stop();
}

/// 주행 중 음성 코너 브리핑 (코파일럿 1호).
///
/// 원칙: 말을 아낀다. 놀랄 코너(타이트 이상)만, 커브당 1회, 콜아웃 간
/// 최소 [cooldown]. 음악은 멈추지 않고 위에 얹는다(iOS duckOthers).
/// TTS 실패는 조용히 무시한다 — 브리핑은 보조 수단이고 앱은 죽지 않는다.
class VoiceBriefingService {
  VoiceBriefingService({
    VoiceSpeak? speak,
    DateTime Function()? clock,
    VoiceTtsFactory? ttsFactory,
  })
    : _speakOverride = speak,
      _clock = clock ?? DateTime.now,
      _ttsFactory = ttsFactory ?? _FlutterVoiceTtsClient.new;

  static const cooldown = Duration(seconds: 8);

  /// 이 창 안에 들어온 커브만 읽는다 (너무 멀면 소음, 너무 가까우면 뒷북).
  static const speakWindowMinM = 50.0;
  static const speakWindowMaxM = 320.0;

  /// 이 시간 이상 커브 큐가 없다가 급코너가 나타나면 "긴 흐름 구간 끝" 패턴.
  static const longClearGap = Duration(seconds: 20);

  final VoiceSpeak? _speakOverride;
  final DateTime Function() _clock;
  final VoiceTtsFactory _ttsFactory;

  VoiceTtsClient? _tts;
  AppLanguage? _ttsLanguage;
  AppLanguage? _voicesLanguage;
  Object? _cachedVoices;
  DateTime? _lastSpokenAt;
  int? _lastSpokenGrade;
  bool _dangerousCooldownInterruptionUsed = false;
  final Set<String> _spokenStages = {};
  DateTime? _lastCueSeenAt;
  bool _startAnnounced = false;

  void announceStart(AppLanguage language, {required bool muted}) {
    if (_startAnnounced || muted) return;
    _startAnnounced = true;
    unawaited(_speak(
      _t(
        language,
        ko: '코너 브리핑을 시작해요. 좋은 드라이브 되세요.',
        en: 'Corner briefing is on. Enjoy the drive.',
        fr: 'Le briefing virages est actif. Bonne route.',
      ),
      language,
    ));
  }

  /// 주행 샘플마다 호출. 조건이 맞을 때만 발화한다.
  void onCue(DriveCurveCue? cue, {required AppLanguage language, required bool muted}) {
    onCoPilotCue(curveCue: cue, language: language, muted: muted);
  }

  /// TBT와 코너 큐를 한 명의 코드라이버 페이스노트로 읽는다.
  void onCoPilotCue({
    NavStep? navStep,
    double? navDistanceM,
    DriveCurveCue? curveCue,
    double? trustedSpeedMps,
    required AppLanguage language,
    required bool muted,
  }) {
    final now = _clock();
    final cue = curveCue;
    if (navStep == null && (cue == null || cue.severity <= 0)) {
      // 큐가 사라짐 = 커브 통과/흐름 구간. 다음 커브를 위해 재무장.
      return;
    }

    // 첫 큐(세션 시작)는 "긴 흐름 뒤"로 치지 않는다 — 관측 이력이 있어야 판정
    final lastSeen = _lastCueSeenAt;
    final hadLongClear =
        lastSeen != null && now.difference(lastSeen) >= longClearGap;
    _lastCueSeenAt = now;

    if (muted) return;
    final distanceM = navDistanceM ?? cue?.distanceM ?? double.infinity;
    final stageKey = _stageKey(
      navStep,
      navDistanceM,
      cue,
      trustedSpeedMps,
    );
    if (stageKey == null || _spokenStages.contains(stageKey)) return;
    if (!_isInSpeakWindow(distanceM, trustedSpeedMps)) {
      return;
    }
    if (navStep == null &&
        (cue == null || cue.severity < 2 || cue.curveCountAhead < 1)) {
      return;
    }

    final last = _lastSpokenAt;
    final inCooldown = last != null && now.difference(last) < cooldown;
    final canInterruptCooldown = inCooldown &&
        !_dangerousCooldownInterruptionUsed &&
        cue != null &&
        cue.grade > 0 &&
        _lastSpokenGrade != null &&
        cue.grade < _lastSpokenGrade!;
    if (inCooldown && !canInterruptCooldown) return;

    final phrase = buildCoPilotPhrase(
      language: language,
      navStep: navStep,
      navDistanceM: navDistanceM,
      curveCue: cue,
      afterLongClear: hadLongClear,
    );
    _lastSpokenAt = now;
    _lastSpokenGrade = cue?.grade;
    if (!inCooldown) _dangerousCooldownInterruptionUsed = false;
    if (canInterruptCooldown) _dangerousCooldownInterruptionUsed = true;
    _spokenStages.add(stageKey);
    _speak(phrase, language);
  }

  void onRouteStatusChange({
    required DriveRouteStatus previous,
    required DriveRouteStatus next,
    required AppLanguage language,
    required bool muted,
    double? rejoinBearing,
  }) {
    if (muted || previous == next) return;
    final phrase = switch ((previous, next)) {
      (DriveRouteStatus.offRoute, DriveRouteStatus.onRoute) => _t(
        language,
        ko: '온 루트',
        en: 'on route',
        fr: 'sur la route',
      ),
      (_, DriveRouteStatus.offRoute) => _t(
        language,
        ko: '루트 이탈 — ${_rejoinSide(language, rejoinBearing)}에서 재진입',
        en: 'off route — rejoin from the ${_rejoinSide(language, rejoinBearing)}',
        fr: 'hors route — reprise par la ${_rejoinSide(language, rejoinBearing)}',
      ),
      _ => null,
    };
    if (phrase == null) return;
    _lastSpokenAt = _clock();
    _speak(phrase, language);
  }

  /// 큐 → 페이스노트. 거리 숫자 + 방향 + 성격만 읽고 조작 지시는 하지 않는다.
  String buildPhrase(
    DriveCurveCue cue, {
    required AppLanguage language,
    bool afterLongClear = false,
  }) {
    return buildCoPilotPhrase(
      language: language,
      curveCue: cue,
      afterLongClear: afterLongClear,
    );
  }

  String buildCoPilotPhrase({
    required AppLanguage language,
    NavStep? navStep,
    double? navDistanceM,
    DriveCurveCue? curveCue,
    bool afterLongClear = false,
  }) {
    final distanceM = navDistanceM ?? curveCue?.distanceM ?? 0;
    final calls = <String>[];
    if (navStep != null) calls.add(navStep.call(language));
    if (curveCue != null && curveCue.curveCountAhead > 0) {
      final curve = _curveCall(curveCue, language);
      calls.add(
        afterLongClear
            ? _t(
                language,
                ko: '긴 흐름 구간 — $curve',
                en: 'long flow — $curve',
                fr: 'section fluide — $curve',
              )
            : curve,
      );
      if (curveCue.curveCountAhead >= 3 && (curveCue.nextGapM ?? 999) <= 280) {
        calls.add(_t(
          language,
          ko: '이어서 연속 ${curveCue.curveCountAhead}개',
          en: 'then ${curveCue.curveCountAhead} in a row',
          fr: 'puis ${curveCue.curveCountAhead} enchaînés',
        ));
      }
    }
    if (calls.isEmpty) return _pacedDistance(distanceM);
    final rest = calls.skip(1).map(
      (call) => navStep == null
          ? call
          : _t(language, ko: '바로 $call', en: 'into $call', fr: call),
    );
    return [
      '${_pacedDistance(distanceM)}, ${calls.first}',
      ...rest,
    ].join(' — ');
  }

  bool _isInSpeakWindow(double distanceM, double? trustedSpeedMps) {
    final speedMps = trustedSpeedMps;
    if (speedMps != null && speedMps.isFinite && speedMps > 0) {
      final ttc = distanceM / speedMps;
      return ttc >= 4 && ttc <= 10;
    }
    return distanceM >= speakWindowMinM && distanceM <= speakWindowMaxM;
  }

  String? _stageKey(
    NavStep? navStep,
    double? navDistanceM,
    DriveCurveCue? cue,
    double? trustedSpeedMps,
  ) {
    final distanceM = navDistanceM ?? cue?.distanceM;
    if (distanceM == null) return null;
    final speedMps = trustedSpeedMps;
    final stage = speedMps != null && speedMps.isFinite && speedMps > 0
        ? (distanceM / speedMps <= 5.5 ? 'near' : 'far')
        : distanceM <= 95
        ? '80'
        : distanceM <= speakWindowMaxM
        ? '300'
        : null;
    if (stage == null) return null;
    if (navStep != null) return 'n:${navStep.sequence}:$stage';
    if (cue == null) return null;
    final cluster = cue.clusterId?.toString() ??
        '${_pacedDistance(distanceM)}:${cue.directionLabel}:'
            '${cue.intensityLabel}:${cue.curveCountAhead}';
    return 'c:$cluster:$stage';
  }

  String _curveCall(DriveCurveCue cue, AppLanguage language) {
    final direction = cue.directionLabel.toLowerCase();
    final left = direction.contains('좌') ||
        direction.contains('left') ||
        direction.contains('gauche');
    final side = left
        ? _t(language, ko: '좌', en: 'left', fr: 'gauche')
        : _t(language, ko: '우', en: 'right', fr: 'droite');
    final intensity = cue.intensityLabel.toLowerCase();
    if (cue.intensityLabel.contains('헤어핀') ||
        intensity.contains('hairpin') ||
        intensity.contains('épingle')) {
      return _t(
        language,
        ko: '헤어핀 $side',
        en: 'hairpin $side',
        fr: 'épingle $side',
      );
    }
    final character = cue.intensityLabel.contains('타이트') ||
            intensity.contains('tight') ||
            intensity.contains('serré')
        ? _t(language, ko: '타이트', en: 'tight', fr: 'serrée')
        : cue.intensityLabel.contains('완만') ||
              intensity.contains('gentle') ||
              intensity.contains('doux')
        ? _t(language, ko: '완만', en: 'gentle', fr: 'douce')
        : cue.intensityLabel;
    return '$side $character';
  }

  String _rejoinSide(AppLanguage language, double? bearing) {
    if (bearing == null) {
      return _t(language, ko: '우측', en: 'right', fr: 'droite');
    }
    final right = (bearing % 360) <= 180;
    return right
        ? _t(language, ko: '우측', en: 'right', fr: 'droite')
        : _t(language, ko: '좌측', en: 'left', fr: 'gauche');
  }

  String _pacedDistance(double meters) {
    if (meters >= 1000) return ((meters / 100).round() * 100).toString();
    return ((meters / 10).round() * 10).clamp(0, 990).toString();
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

  Future<VoiceTtsClient?> _ensureTts(AppLanguage language) async {
    try {
      var tts = _tts;
      if (tts == null) {
        tts = _ttsFactory();
        await tts.configureAudioSession();
        await tts.setSpeechRate(
          defaultTargetPlatform == TargetPlatform.iOS ? 0.52 : 0.5,
        );
        await tts.setPitch(1.0);
        _tts = tts;
      }
      if (_ttsLanguage != language) {
        final locale = switch (language) {
          AppLanguage.korean => 'ko-KR',
          AppLanguage.french => 'fr-CA',
          _ => 'en-US',
        };
        await tts.setLanguage(locale);
        await _selectEnhancedVoice(tts, language, locale);
        _ttsLanguage = language;
      }
      return tts;
    } catch (_) {
      return null;
    }
  }

  Future<void> _selectEnhancedVoice(
    VoiceTtsClient tts,
    AppLanguage language,
    String locale,
  ) async {
    try {
      if (_voicesLanguage != language) {
        _cachedVoices = await tts.getVoices();
        _voicesLanguage = language;
      }
      final voice = _enhancedVoiceFor(_cachedVoices, locale);
      if (voice != null) await tts.setVoice(voice);
    } catch (_) {
      // Enhanced voice 선택 실패는 기본 보이스로 계속 진행한다.
    }
  }

  Map<String, String>? _enhancedVoiceFor(Object? voices, String locale) {
    if (voices is! Iterable) return null;
    for (final voice in voices) {
      final candidate = _voiceMap(voice, locale);
      if (candidate == null) continue;
      final name = candidate['name']?.toLowerCase() ?? '';
      final quality = candidate['quality']?.toLowerCase() ?? '';
      if (!_matchesLocale(candidate, locale)) continue;
      if (!name.contains('enhanced') &&
          !name.contains('premium') &&
          !quality.contains('enhanced') &&
          !quality.contains('premium')) {
        continue;
      }
      return {
        'name': candidate['name']!,
        'locale': candidate['locale'] ?? locale,
      };
    }
    return null;
  }

  Map<String, String>? _voiceMap(Object? voice, String locale) {
    if (voice is! Map) return null;
    final name = _voiceField(voice, const ['name', 'identifier']);
    if (name == null || name.isEmpty) return null;
    final quality = _voiceField(voice, const ['quality']);
    final result = {
      'name': name,
      'locale': _voiceField(voice, const ['locale', 'language']) ?? locale,
    };
    if (quality != null) result['quality'] = quality;
    return result;
  }

  String? _voiceField(Map<dynamic, dynamic> voice, List<String> keys) {
    for (final key in keys) {
      final value = voice[key] ?? voice[key.toUpperCase()];
      if (value != null) return value.toString();
    }
    return null;
  }

  bool _matchesLocale(Map<String, String> voice, String locale) {
    final expected = locale.toLowerCase();
    final voiceLocale = voice['locale']?.toLowerCase() ?? '';
    final name = voice['name']?.toLowerCase() ?? '';
    return voiceLocale.startsWith(expected) || name.startsWith(expected);
  }

  void dispose() {
    try {
      unawaited(_tts?.stop());
    } catch (_) {}
    _tts = null;
  }

  String _t(AppLanguage language, {required String ko, required String en, required String fr}) {
    return switch (language) {
      AppLanguage.korean => ko,
      AppLanguage.french => fr,
      _ => en,
    };
  }
}

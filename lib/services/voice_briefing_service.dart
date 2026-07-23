import 'dart:async';
import 'dart:math' as math;

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
    setSharedInstance: _tts.setSharedInstance,
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
/// 원칙: 랠리 코드라이버처럼 읽는다 — 의미 있는 코너(중간 이상)는 하나도
/// 빼놓지 않고, 코너당 정확히 1회, 발화 사이 최소 [minGap]. 부를 시점은
/// 거리가 아니라 **시간**으로 잡는다([curveLeadSeconds]) — 고정 미터 창은
/// 저속에선 너무 이르고 고속에선 뒷북이었다.
/// 음악은 멈추지 않고 위에 얹는다(iOS duckOthers).
/// TTS 실패는 조용히 무시한다 — 브리핑은 보조 수단이고 앱은 죽지 않는다.
class VoiceBriefingService {
  VoiceBriefingService({
    VoiceSpeak? speak,
    DateTime Function()? clock,
    VoiceTtsFactory? ttsFactory,
  }) : _speakOverride = speak,
       _clock = clock ?? DateTime.now,
       _ttsFactory = ttsFactory ?? _FlutterVoiceTtsClient.new;

  /// 발화 사이 안전 하한. 이전 발화가 길면 그만큼 더 벌린다(문장 잘림 방지).
  static const minGap = Duration(seconds: 4);

  /// 코너를 몇 초 앞에서 부를지 / 그 거리의 하한·상한.
  static const curveLeadSeconds = 7.0;
  static const curveLeadMinM = 70.0;
  static const curveLeadMaxM = 400.0;

  /// 이보다 가까우면 이미 코너 안 — 뒷북 대신 조용히 넘긴다.
  static const curveFloorSeconds = 2.5;

  /// 분기/교차로(TBT)는 코너보다 일찍, 두 단계로 부른다.
  static const navLeadSeconds = 20.0;
  static const navLeadMinM = 150.0;
  static const navLeadMaxM = 450.0;
  static const navNearSeconds = 5.0;
  static const navNearMinM = 60.0;

  /// 속도를 모를 때 기준값 (정지/GPS 공백 구간).
  static const defaultSpeedKmh = 60.0;

  /// 이 시간 이상 커브 큐가 없다가 급코너가 나타나면 "긴 흐름 구간 끝" 패턴.
  static const longClearGap = Duration(seconds: 20);

  /// 같은 코너를 두 번 읽지 않기 위한 기억. 무한정 자라지 않게 상한을 둔다.
  static const _spokenMemoryLimit = 400;

  final VoiceSpeak? _speakOverride;
  final DateTime Function() _clock;
  final VoiceTtsFactory _ttsFactory;

  VoiceTtsClient? _tts;
  AppLanguage? _ttsLanguage;
  AppLanguage? _voicesLanguage;
  Object? _cachedVoices;
  DateTime? _lastSpokenAt;
  Duration _lastSpeechEstimate = Duration.zero;
  final Set<int> _spokenCorners = {};
  final Set<String> _spokenNavStages = {};
  DateTime? _lastCueSeenAt;
  bool _startAnnounced = false;

  void announceStart(AppLanguage language, {required bool muted}) {
    if (_startAnnounced || muted) return;
    _startAnnounced = true;
    final phrase = _t(
      language,
      ko: '코너 브리핑을 시작해요. 좋은 드라이브 되세요.',
      en: 'Corner briefing is on. Enjoy the drive.',
      fr: 'Le briefing virages est actif. Bonne route.',
    );
    // 첫 코너 콜이 인사말을 잘라먹지 않게 간격 계산에 포함시킨다.
    _lastSpokenAt = _clock();
    _lastSpeechEstimate = _estimateSpeech(phrase, language);
    unawaited(_speak(phrase, language));
  }

  /// 주행 샘플마다 호출. 조건이 맞을 때만 발화한다.
  void onCue(
    DriveCurveCue? cue, {
    required AppLanguage language,
    required bool muted,
    double? speedKmh,
  }) {
    onCoPilotCue(
      curveCue: cue,
      language: language,
      muted: muted,
      speedKmh: speedKmh,
    );
  }

  /// TBT와 코너 큐를 한 명의 코드라이버 페이스노트로 읽는다.
  ///
  /// 분기 콜과 코너 콜은 **각자의 창**으로 판정한다. 예전에는 다음 분기까지의
  /// 거리가 곧 게이트여서, 교차로 없는 산길(다음 분기 6km)에 들어서면 코너
  /// 브리핑이 통째로 사라졌다.
  void onCoPilotCue({
    NavStep? navStep,
    double? navDistanceM,
    DriveCurveCue? curveCue,
    double? speedKmh,
    required AppLanguage language,
    required bool muted,
  }) {
    final now = _clock();
    final cue = curveCue;
    final hasCurve = cue != null && cue.severity > 0 && cue.curveCountAhead > 0;

    // 첫 큐(세션 시작)는 "긴 흐름 뒤"로 치지 않는다 — 관측 이력이 있어야 판정
    final lastSeen = _lastCueSeenAt;
    final hadLongClear =
        lastSeen != null && now.difference(lastSeen) >= longClearGap;
    if (hasCurve) _lastCueSeenAt = now;
    if (muted) return;

    final mps = (speedKmh ?? defaultSpeedKmh).clamp(5.0, 200.0) / 3.6;

    final navStage = navStep == null || navDistanceM == null
        ? null
        : _navStage(navDistanceM, mps);
    final navKey = navStage == null ? null : 'n:${navStep!.sequence}:$navStage';
    final navReady = navKey != null && !_spokenNavStages.contains(navKey);

    final curveReady = hasCurve && _curveReady(cue, mps);

    if (!navReady && !curveReady) return;

    // 분기와 코너가 붙어 있으면 한 문장으로 묶는다 ("300, 우측 갈림길 — 바로 좌 타이트")
    final merge =
        navReady && curveReady && cue.distanceM <= (navDistanceM ?? 0) + 150;
    final speakNav =
        navReady && (merge || !curveReady || _navFirst(navDistanceM, cue));
    final speakCurve = curveReady && (merge || !speakNav);

    final phrase = buildCoPilotPhrase(
      language: language,
      navStep: speakNav ? navStep : null,
      navDistanceM: speakNav ? navDistanceM : null,
      curveCue: speakCurve ? cue : null,
      afterLongClear: speakCurve && hadLongClear,
    );

    // 간격이 아직 안 찼으면 아무것도 소비하지 않는다 — 다음 샘플에서 다시 시도.
    final last = _lastSpokenAt;
    if (last != null && now.difference(last) < _requiredGap) return;

    if (speakNav) _remember(_spokenNavStages, navKey);
    if (speakCurve) {
      _remember(_spokenCorners, cue.cornerId);
      // 링크로 함께 읽은 코너는 다시 부르지 않는다 ("짧게 우 타이트"를 듣고
      // 20초 뒤 같은 코너를 또 듣는 건 페이스노트가 아니다).
      final linked = cue.nextCornerId;
      if (linked != null && _linkCall(cue, language) != null) {
        _remember(_spokenCorners, linked);
      }
    }
    _lastSpokenAt = now;
    _lastSpeechEstimate = _estimateSpeech(phrase, language);
    _speak(phrase, language);
  }

  /// 코너를 지금 부를 차례인가. 이미 지나쳤으면 조용히 소거한다(뒷북 금지).
  bool _curveReady(DriveCurveCue cue, double mps) {
    if (_spokenCorners.contains(cue.cornerId)) return false;
    final floorM = math.max(mps * curveFloorSeconds, 12.0);
    if (cue.distanceM < floorM) {
      _remember(_spokenCorners, cue.cornerId);
      return false;
    }
    final leadM = (mps * curveLeadSeconds).clamp(curveLeadMinM, curveLeadMaxM);
    return cue.distanceM <= leadM;
  }

  String? _navStage(double navDistanceM, double mps) {
    final nearM = math.max(mps * navNearSeconds, navNearMinM);
    if (navDistanceM <= nearM) return 'near';
    final leadM = (mps * navLeadSeconds).clamp(navLeadMinM, navLeadMaxM);
    if (navDistanceM <= leadM) return 'far';
    return null;
  }

  bool _navFirst(double? navDistanceM, DriveCurveCue cue) {
    return (navDistanceM ?? double.infinity) <= cue.distanceM;
  }

  Duration get _requiredGap {
    final tail = _lastSpeechEstimate + const Duration(milliseconds: 1200);
    return tail > minGap ? tail : minGap;
  }

  /// 한국어는 음절당 발화가 길다 — 언어별로 문장 길이를 초로 환산한다.
  Duration _estimateSpeech(String phrase, AppLanguage language) {
    final perChar = switch (language) {
      AppLanguage.english => 0.075,
      AppLanguage.french => 0.09,
      _ => 0.2,
    };
    final seconds = (phrase.length * perChar).clamp(1.0, 6.0);
    return Duration(milliseconds: (seconds * 1000).round());
  }

  void _remember<T>(Set<T> memory, T key) {
    if (memory.length >= _spokenMemoryLimit) memory.clear();
    memory.add(key);
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
    _lastSpeechEstimate = _estimateSpeech(phrase, language);
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
      final link = _linkCall(curveCue, language);
      if (link != null) {
        calls.add(link);
      } else if (curveCue.curveCountAhead >= 3 &&
          (curveCue.nextGapM ?? 999) <= 280) {
        calls.add(
          _t(
            language,
            ko: '이어서 연속 ${curveCue.curveCountAhead}개',
            en: 'then ${curveCue.curveCountAhead} in a row',
            fr: 'puis ${curveCue.curveCountAhead} enchaînés',
          ),
        );
      }
    }
    if (calls.isEmpty) return _pacedDistance(distanceM);
    final rest = <String>[];
    for (var i = 1; i < calls.length; i++) {
      rest.add(
        i == 1 && navStep != null
            ? _t(
                language,
                ko: '바로 ${calls[i]}',
                en: 'into ${calls[i]}',
                fr: calls[i],
              )
            : calls[i],
      );
    }
    return [
      '${_pacedDistance(distanceM)}, ${calls.first}',
      ...rest,
    ].join(' — ');
  }

  /// 바로 이어지는 다음 코너를 한 호흡에 붙여 읽는다 ("좌 타이트 — 짧게 우 중간").
  /// 연속 코너에서 매 코너마다 문장을 새로 시작하지 않게 해 준다.
  String? _linkCall(DriveCurveCue cue, AppLanguage language) {
    final direction = cue.nextDirectionLabel;
    final intensity = cue.nextIntensityLabel;
    final gapM = cue.nextGapM;
    if (direction == null || intensity == null || gapM == null) return null;
    if (gapM > 140) return null;
    final next = _call(direction, intensity, language);
    return _t(
      language,
      ko: '짧게 $next',
      en: 'short into $next',
      fr: 'court puis $next',
    );
  }

  String _curveCall(DriveCurveCue cue, AppLanguage language) {
    return _call(cue.directionLabel, cue.intensityLabel, language);
  }

  String _call(
    String directionLabel,
    String intensityLabel,
    AppLanguage language,
  ) {
    final direction = directionLabel.toLowerCase();
    final left =
        direction.contains('좌') ||
        direction.contains('left') ||
        direction.contains('gauche');
    final side = left
        ? _t(language, ko: '좌', en: 'left', fr: 'gauche')
        : _t(language, ko: '우', en: 'right', fr: 'droite');
    final intensity = intensityLabel.toLowerCase();
    if (intensityLabel.contains('헤어핀') ||
        intensity.contains('hairpin') ||
        intensity.contains('épingle')) {
      return _t(
        language,
        ko: '헤어핀 $side',
        en: 'hairpin $side',
        fr: 'épingle $side',
      );
    }
    final character =
        intensityLabel.contains('타이트') ||
            intensity.contains('tight') ||
            intensity.contains('serré')
        ? _t(language, ko: '타이트', en: 'tight', fr: 'serrée')
        : intensityLabel.contains('완만') ||
              intensity.contains('gentle') ||
              intensity.contains('doux')
        ? _t(language, ko: '완만', en: 'gentle', fr: 'douce')
        : intensityLabel;
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
        await tts.setSpeechRate(
          defaultTargetPlatform == TargetPlatform.iOS ? 0.52 : 0.5,
        );
        await tts.setPitch(1.0);
        _tts = tts;
      }
      // 워키 녹음(playAndRecord) 등 다른 오디오가 세션 카테고리를 가져가면
      // 그 뒤 브리핑이 안 들린다 — 발화 직전마다 playback+ducking으로 되돌린다.
      await tts.configureAudioSession();
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

  String _t(
    AppLanguage language, {
    required String ko,
    required String en,
    required String fr,
  }) {
    return switch (language) {
      AppLanguage.korean => ko,
      AppLanguage.french => fr,
      _ => en,
    };
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../core/app_language.dart';
import '../ui/route_drive_cue.dart';
import 'audio_session.dart';
import 'drive_elevation_cue.dart';
import 'route_turn_service.dart';

/// TTS 발화 시임 — 테스트에서 fake 주입.
typedef VoiceSpeak = Future<void> Function(String text, AppLanguage language);
typedef VoiceTtsFactory = VoiceTtsClient Function();
typedef VoiceDebugLog = void Function(String message);

void _defaultVoiceDebugLog(String message) => debugPrint(message);

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

/// One accepted location sample's complete, position-aligned voice evidence.
/// Route-wide aggregates deliberately do not belong in this frame.
@immutable
class DriveCoPilotFrame {
  const DriveCoPilotFrame({
    required this.previousStatus,
    required this.nextStatus,
    required this.language,
    required this.muted,
    this.navStep,
    this.navDistanceM,
    this.navNamespace = 'route',
    this.curveCue,
    this.elevationCue,
    this.preferCurve = false,
    this.rejoinBearing,
    this.currentHeading,
  });

  final DriveRouteStatus previousStatus;
  final DriveRouteStatus nextStatus;
  final AppLanguage language;
  final bool muted;
  final NavStep? navStep;
  final double? navDistanceM;
  final String navNamespace;
  final DriveCurveCue? curveCue;
  final DriveElevationCue? elevationCue;
  final bool preferCurve;
  final double? rejoinBearing;
  final double? currentHeading;
}

class _FlutterVoiceTtsClient implements VoiceTtsClient {
  _FlutterVoiceTtsClient() : _tts = FlutterTts();

  final FlutterTts _tts;

  @override
  Future<void> configureAudioSession() async {
    await configureMusicDuckingAudioSession(
      setIosAudioCategory: _tts.setIosAudioCategory,
    );
    await _tts.awaitSpeakCompletion(true);
  }

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
    VoiceDebugLog? debugLog,
  }) : _speakOverride = speak,
       _clock = clock ?? DateTime.now,
       _ttsFactory = ttsFactory ?? _FlutterVoiceTtsClient.new,
       _debugLog = debugLog ?? _defaultVoiceDebugLog;

  static const cooldown = Duration(seconds: 5);

  /// 이 창 안에 들어온 커브만 읽는다 (너무 멀면 소음, 너무 가까우면 뒷북).
  static const speakWindowMinM = 50.0;
  static const speakWindowMaxM = 320.0;

  /// Two facts share one distance only when their along-route positions are
  /// close enough that the compact call cannot mislead the driver.
  static const mergeWindowM = 100.0;

  /// 이 시간 이상 커브 큐가 없다가 급코너가 나타나면 "긴 흐름 구간 끝" 패턴.
  static const longClearGap = Duration(seconds: 20);

  final VoiceSpeak? _speakOverride;
  final DateTime Function() _clock;
  final VoiceTtsFactory _ttsFactory;
  final VoiceDebugLog _debugLog;

  VoiceTtsClient? _tts;
  AppLanguage? _ttsLanguage;
  AppLanguage? _voicesLanguage;
  Object? _cachedVoices;
  DateTime? _lastSpokenAt;
  double? _spokenDistanceM;
  final Set<String> _spokenStages = {};
  DateTime? _lastCueSeenAt;
  DateTime? _curveClearSince;
  Future<void> _speechQueue = Future.value();
  bool _disposed = false;

  /// 시작 인사는 운전 판단 정보가 아니므로 의도적으로 읽지 않는다.
  void announceStart(AppLanguage language, {required bool muted}) {
    // Intentionally silent.
  }

  /// 주행 샘플마다 호출. 조건이 맞을 때만 발화한다.
  void onCue(
    DriveCurveCue? cue, {
    required AppLanguage language,
    required bool muted,
  }) {
    onCoPilotCue(curveCue: cue, language: language, muted: muted);
  }

  /// Selects at most one call for one drive sample. A route-state transition
  /// preempts every lower-priority maneuver/curve/elevation fact.
  void onDriveFrame(DriveCoPilotFrame frame) {
    final hasPriorityStatusCall =
        frame.previousStatus != frame.nextStatus &&
        (frame.nextStatus == DriveRouteStatus.offRoute ||
            (frame.previousStatus == DriveRouteStatus.offRoute &&
                frame.nextStatus == DriveRouteStatus.onRoute));
    if (hasPriorityStatusCall) {
      onRouteStatusChange(
        previous: frame.previousStatus,
        next: frame.nextStatus,
        language: frame.language,
        muted: frame.muted,
        rejoinBearing: frame.rejoinBearing,
        currentHeading: frame.currentHeading,
      );
      return;
    }
    if (frame.nextStatus != DriveRouteStatus.onRoute &&
        frame.nextStatus != DriveRouteStatus.completed) {
      return;
    }
    onCoPilotCue(
      navStep: frame.navStep,
      navDistanceM: frame.navDistanceM,
      navNamespace: frame.navNamespace,
      curveCue: frame.curveCue,
      elevationCue: frame.elevationCue,
      preferCurve: frame.preferCurve,
      language: frame.language,
      muted: frame.muted,
    );
  }

  /// TBT와 코너 큐를 한 명의 코드라이버 페이스노트로 읽는다.
  void onCoPilotCue({
    NavStep? navStep,
    double? navDistanceM,
    String navNamespace = 'route',
    DriveCurveCue? curveCue,
    DriveElevationCue? elevationCue,
    bool preferCurve = false,
    required AppLanguage language,
    required bool muted,
  }) {
    final now = _clock();
    final observedCurveCue = _briefableCurve(curveCue);
    var spokenCurveCue = observedCurveCue;
    final candidateNavStep = _briefableNavStep(navStep);
    final curveTakesPriority =
        (preferCurve || candidateNavStep?.isStraightAhead == true) &&
        spokenCurveCue != null &&
        spokenCurveCue.distanceM >= speakWindowMinM &&
        spokenCurveCue.distanceM <= speakWindowMaxM;
    var spokenNavStep = curveTakesPriority && !preferCurve
        ? null
        : candidateNavStep;
    var spokenNavDistanceM = spokenNavStep == null ? null : navDistanceM;
    if (spokenNavStep != null &&
        spokenNavDistanceM != null &&
        spokenCurveCue != null &&
        (spokenNavDistanceM - spokenCurveCue.distanceM).abs() > mergeWindowM) {
      if (preferCurve || spokenNavStep.isStraightAhead) {
        spokenNavStep = null;
        spokenNavDistanceM = null;
      } else {
        spokenCurveCue = null;
      }
    }
    if (observedCurveCue == null) {
      // One missing GPS sample must not re-arm the same physical curve.
      _curveClearSince ??= now;
      if (now.difference(_curveClearSince!) >= const Duration(seconds: 3)) {
        _spokenDistanceM = null;
        _spokenStages.removeWhere((key) => key.startsWith('c:'));
      }
    } else {
      final clearSince = _curveClearSince;
      if (clearSince != null &&
          now.difference(clearSince) >= const Duration(seconds: 3)) {
        _spokenDistanceM = null;
        _spokenStages.removeWhere((key) => key.startsWith('c:'));
      }
      _curveClearSince = null;
    }
    if (spokenNavStep == null && spokenCurveCue == null) {
      onElevationCue(elevationCue, language: language, muted: muted);
      return;
    }

    // 첫 큐(세션 시작)는 "긴 흐름 뒤"로 치지 않는다 — 관측 이력이 있어야 판정
    final lastSeen = _lastCueSeenAt;
    final hadLongClear =
        lastSeen != null && now.difference(lastSeen) >= longClearGap;
    _lastCueSeenAt = now;

    if (muted) return;
    final distanceM = preferCurve && spokenCurveCue != null
        ? spokenCurveCue.distanceM
        : spokenNavDistanceM ?? spokenCurveCue?.distanceM ?? double.infinity;
    final stageKey = _stageKey(
      spokenNavStep,
      spokenNavDistanceM,
      spokenCurveCue,
      navNamespace,
      preferCurve: preferCurve,
    );
    if (stageKey == null || _spokenStages.contains(stageKey)) return;
    final isFinish =
        spokenNavStep?.maneuverType.trim().toLowerCase() == 'arrive';
    final atStraightStart =
        spokenNavStep?.isStraightAhead == true && distanceM <= 25;
    if (!isFinish &&
        !atStraightStart &&
        (distanceM < speakWindowMinM || distanceM > speakWindowMaxM)) {
      return;
    }
    if (spokenNavStep?.isStraightAhead == true &&
        distanceM <= 95 &&
        !atStraightStart) {
      return;
    }

    // 같은 커브 접근 중 재발화 방지: 발화 후 거리가 크게 늘어나야(=새 커브) 재무장
    final spokenAt = _spokenDistanceM;
    if (spokenNavStep == null &&
        spokenAt != null &&
        distanceM <= spokenAt + 120) {
      return;
    }

    final last = _lastSpokenAt;
    if (last != null && now.difference(last) < cooldown) return;

    final phrase = buildCoPilotPhrase(
      language: language,
      navStep: spokenNavStep,
      navDistanceM: spokenNavDistanceM,
      curveCue: spokenCurveCue,
      elevationCue: elevationCue,
      afterLongClear: hadLongClear,
      preferCurve: preferCurve,
    );
    _lastSpokenAt = now;
    if (spokenCurveCue != null) {
      _spokenDistanceM = spokenCurveCue.distanceM;
    }
    _spokenStages.add(stageKey);
    if (spokenNavStep != null && spokenCurveCue != null) {
      _spokenStages
        ..add(_navStageKey(spokenNavStep, navNamespace))
        ..add(_curveStageKey(spokenCurveCue));
    }
    if (_shouldIncludeElevation(
      navStep: spokenNavStep,
      navDistanceM: spokenNavDistanceM,
      curveCue: spokenCurveCue,
      elevationCue: elevationCue,
      primaryDistanceM: distanceM,
    )) {
      _spokenStages.add('e:${elevationCue!.stageId}');
    }
    _speak(phrase, language);
  }

  void onRouteStatusChange({
    required DriveRouteStatus previous,
    required DriveRouteStatus next,
    required AppLanguage language,
    required bool muted,
    double? rejoinBearing,
    double? currentHeading,
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
        ko: '루트 이탈, ${_rejoinSide(language, rejoinBearing, currentHeading)} 재진입',
        en: 'off route, rejoin ${_rejoinSide(language, rejoinBearing, currentHeading)}',
        fr: 'hors route, reprise à ${_rejoinSide(language, rejoinBearing, currentHeading)}',
      ),
      _ => null,
    };
    if (phrase == null) return;
    _lastSpokenAt = _clock();
    _speak(phrase, language);
  }

  /// Announces one meaningful climb/descent event. The shared cooldown means
  /// an immediate curve or navigation call always wins the current sample.
  void onElevationCue(
    DriveElevationCue? cue, {
    required AppLanguage language,
    required bool muted,
  }) {
    if (cue == null || muted) return;
    final stageKey = 'e:${cue.stageId}';
    if (_spokenStages.contains(stageKey)) return;
    final now = _clock();
    final last = _lastSpokenAt;
    if (last != null && now.difference(last) < cooldown) return;
    _lastSpokenAt = now;
    _spokenStages.add(stageKey);
    _speak(buildElevationPhrase(cue, language: language), language);
  }

  String buildElevationPhrase(
    DriveElevationCue cue, {
    required AppLanguage language,
  }) {
    final roundedChange = ((cue.changeM / 10).round() * 10).clamp(10, 9990);
    if (cue.isCrest) {
      final roundedDescent = (((cue.followingChangeM ?? 0) / 10).round() * 10)
          .clamp(10, 9990);
      final call = _t(
        language,
        ko: '크레스트, 상승 $roundedChange, 하강 $roundedDescent',
        en: 'crest, $roundedChange up, $roundedDescent down',
        fr: 'crête, montée $roundedChange, descente $roundedDescent',
      );
      if (cue.distanceM < 100) return call;
      return '${_pacedDistance(cue.distanceM)}, $call';
    }
    final call = switch ((language, cue.trend)) {
      (AppLanguage.korean, DriveElevationTrend.uphill) =>
        '오르막, 상승 $roundedChange미터',
      (AppLanguage.korean, DriveElevationTrend.downhill) =>
        '내리막, 하강 $roundedChange미터',
      (AppLanguage.french, DriveElevationTrend.uphill) =>
        'montée, $roundedChange mètres',
      (AppLanguage.french, DriveElevationTrend.downhill) =>
        'descente, $roundedChange mètres',
      (AppLanguage.english, DriveElevationTrend.uphill) =>
        'climb, $roundedChange meters',
      (AppLanguage.english, DriveElevationTrend.downhill) =>
        'descent, $roundedChange meters',
    };
    if (cue.distanceM < 100) return call;
    return '${_pacedDistance(cue.distanceM)}, $call';
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
    DriveElevationCue? elevationCue,
    bool afterLongClear = false,
    bool preferCurve = false,
  }) {
    final spokenNavStep = _briefableNavStep(navStep);
    final distanceM = preferCurve && curveCue != null
        ? curveCue.distanceM
        : spokenNavStep == null
        ? curveCue?.distanceM ?? 0
        : navDistanceM ?? 0;
    final navCall = spokenNavStep == null
        ? null
        : _navCall(spokenNavStep, language);
    String? curveCall;
    String? sequenceCall;
    if (curveCue != null && curveCue.curveCountAhead > 0) {
      final curve = _curveCall(curveCue, language);
      curveCall = curve;
      sequenceCall = _curveSequenceCall(curveCue, language);
    }
    final primaryCall = preferCurve
        ? curveCall ?? navCall
        : navCall ?? curveCall;
    if (primaryCall == null) return _pacedDistance(distanceM);
    if (spokenNavStep?.maneuverType == 'arrive') return primaryCall;
    final atStraightStart =
        spokenNavStep?.isStraightAhead == true && (navDistanceM ?? 999) <= 25;
    final calls = <String>[
      atStraightStart
          ? primaryCall
          : '${_pacedDistance(distanceM)}, $primaryCall',
    ];
    String? secondaryCall;
    if (navCall != null &&
        curveCall != null &&
        ((navDistanceM ?? double.infinity) - curveCue!.distanceM).abs() <=
            mergeWindowM) {
      secondaryCall = preferCurve ? navCall : curveCall;
    }
    if (secondaryCall != null &&
        _repeatsDirection(primaryCall, secondaryCall, language)) {
      secondaryCall = null;
    }
    final includeElevation = _shouldIncludeElevation(
      navStep: spokenNavStep,
      navDistanceM: navDistanceM,
      curveCue: curveCue,
      elevationCue: elevationCue,
      primaryDistanceM: distanceM,
    );
    if (includeElevation) {
      if (elevationCue!.isCrest && secondaryCall == null) {
        secondaryCall = _elevationCall(elevationCue, language);
      }
    }
    secondaryCall ??= sequenceCall;
    if (secondaryCall == null && includeElevation) {
      secondaryCall = _elevationCall(elevationCue!, language);
    }
    if (secondaryCall != null) calls.add(secondaryCall);
    return calls.join(', ');
  }

  bool _shouldIncludeElevation({
    required NavStep? navStep,
    required double? navDistanceM,
    required DriveCurveCue? curveCue,
    required DriveElevationCue? elevationCue,
    required double primaryDistanceM,
  }) {
    if (elevationCue == null ||
        (elevationCue.distanceM - primaryDistanceM).abs() > mergeWindowM) {
      return false;
    }
    final navAndCurveAlreadyMerged =
        navStep != null &&
        navDistanceM != null &&
        curveCue != null &&
        (navDistanceM - curveCue.distanceM).abs() <= mergeWindowM;
    if (navAndCurveAlreadyMerged) return false;
    if (elevationCue.isCrest) return true;
    return curveCue == null || curveCue.curveCountAhead < 2;
  }

  NavStep? _briefableNavStep(NavStep? step) {
    if (step == null) return null;
    return step.isBriefingWorthy ? step : null;
  }

  DriveCurveCue? _briefableCurve(DriveCurveCue? cue) {
    if (cue == null || cue.curveCountAhead < 1) return null;
    if (cue.severity >= 2) return cue;
    if (cue.severity >= 1 &&
        cue.curveCountAhead >= 2 &&
        (cue.nextGapM ?? double.infinity) <= 280) {
      return cue;
    }
    return null;
  }

  String _navCall(NavStep step, AppLanguage language) {
    if (!step.isStraightAhead) return step.call(language);
    final kilometers = (step.segmentDistanceM / 100).round() / 10;
    final distance = kilometers == kilometers.roundToDouble()
        ? kilometers.toStringAsFixed(0)
        : kilometers.toStringAsFixed(1);
    final singular = kilometers == 1;
    return _t(
      language,
      ko: '직진 $distance킬로',
      en: 'straight $distance ${singular ? 'kilometer' : 'kilometers'}',
      fr: 'tout droit ${distance.replaceAll('.', ',')} ${singular ? 'kilomètre' : 'kilomètres'}',
    );
  }

  String? _curveSequenceCall(DriveCurveCue cue, AppLanguage language) {
    if (cue.curveCountAhead < 2) return null;
    return _t(
      language,
      ko: '연속 커브',
      en: 'bends continue',
      fr: 'virages enchaînés',
    );
  }

  String _elevationCall(DriveElevationCue cue, AppLanguage language) {
    if (cue.isCrest) {
      return _t(language, ko: '크레스트', en: 'crest', fr: 'crête');
    }
    final roundedChange = ((cue.changeM / 10).round() * 10).clamp(10, 9990);
    return switch ((language, cue.trend)) {
      (AppLanguage.korean, DriveElevationTrend.uphill) => '오르막 $roundedChange',
      (AppLanguage.korean, DriveElevationTrend.downhill) =>
        '내리막 $roundedChange',
      (AppLanguage.french, DriveElevationTrend.uphill) =>
        'montée $roundedChange',
      (AppLanguage.french, DriveElevationTrend.downhill) =>
        'descente $roundedChange',
      (AppLanguage.english, DriveElevationTrend.uphill) =>
        'climb $roundedChange',
      (AppLanguage.english, DriveElevationTrend.downhill) =>
        'descent $roundedChange',
    };
  }

  String? _stageKey(
    NavStep? navStep,
    double? navDistanceM,
    DriveCurveCue? cue,
    String navNamespace, {
    bool preferCurve = false,
  }) {
    final distanceM = navDistanceM ?? cue?.distanceM;
    if (distanceM == null) return null;
    if (preferCurve && cue != null) return _curveStageKey(cue);
    if (navStep != null) {
      return _navStageKey(navStep, navNamespace);
    }
    final stage = distanceM <= 95
        ? '80'
        : distanceM <= speakWindowMaxM
        ? '300'
        : null;
    if (stage == null) return null;
    if (cue == null) return null;
    return _curveStageKey(cue, stage: stage);
  }

  String _navStageKey(NavStep step, String namespace) =>
      'n:$namespace:${step.sequence}:approach';

  /// 이미 말한 커브인지 가리는 키. 표시용 번역 문자열을 신원에 넣으면 주행 중
  /// 언어를 바꾸는 것만으로 같은 커브가 새 커브가 되므로, 강도는 `severity`로
  /// 잡는다.
  String _curveStageKey(DriveCurveCue cue, {String? stage}) {
    final distanceStage = stage ?? (cue.distanceM <= 95 ? '80' : '300');
    return 'c:${_pacedDistance(cue.distanceM)}:${cue.directionLabel}:'
        '${cue.severity}:${cue.curveCountAhead}:$distanceStage';
  }

  /// 중간 강도 커브의 콜은 방향어 하나뿐이라("right"), nav 콜이 이미 같은 방향을
  /// 말했으면 "310, turn right, right"처럼 정보 없이 반복된다. 그럴 땐 두 번째
  /// 자리를 비워 시퀀스("bends continue")나 고저차 콜이 대신 들어가게 한다.
  bool _repeatsDirection(
    String primaryCall,
    String secondaryCall,
    AppLanguage language,
  ) {
    final secondary = secondaryCall.trim().toLowerCase();
    final primary = primaryCall.toLowerCase();
    for (final side in [
      _t(language, ko: '좌측', en: 'left', fr: 'gauche'),
      _t(language, ko: '우측', en: 'right', fr: 'droite'),
    ]) {
      final word = side.toLowerCase();
      if (secondary == word) return primary.contains(word);
    }
    return false;
  }

  String _curveCall(DriveCurveCue cue, AppLanguage language) {
    final direction = cue.directionLabel.toLowerCase();
    final left =
        direction.contains('좌') ||
        direction.contains('left') ||
        direction.contains('gauche');
    final right =
        direction.contains('우') ||
        direction.contains('right') ||
        direction.contains('droite');
    final side = left
        ? _t(language, ko: '좌측', en: 'left', fr: 'gauche')
        : right
        ? _t(language, ko: '우측', en: 'right', fr: 'droite')
        : null;
    // 강도는 `severity`로 읽는다. 예전에는 `intensityLabel`에 'tight'/'gentle'이
    // 들어있는지 검사했는데, 그 라벨은 화면에 그대로 찍히는 번역 문자열이라
    // 표시 문구를 바꾸는 순간 조용히 끊어졌다 (8db6043이 '타이트'를 '급커브'로
    // 바꾸면서 실제로 끊어졌고, 모든 코너가 등급 없이 "turn right"로 나왔다).
    // severity는 라벨과 같은 임계값(_curveSeverity)에서 나오고 이미
    // `_briefableCurve`가 쓰는 값이라, 문구를 바꿔도 음성은 안 깨진다.
    if (cue.severity >= 3) {
      return _t(
        language,
        ko: side == null ? '급회전' : '$side 급회전',
        en: side == null ? 'very sharp turn' : 'very sharp $side',
        fr: side == null ? 'virage très serré' : '$side très serrée',
      );
    }
    final tight = cue.severity == 2;
    final gentle = cue.severity <= 0;
    final medium = cue.severity == 1;
    return switch (language) {
      AppLanguage.korean =>
        '${side == null ? '' : '$side '}${tight
            ? '급커브'
            : gentle
            ? '완만한 커브'
            : medium
            ? '커브'
            : '커브'}',
      AppLanguage.french =>
        side == null
            ? tight
                  ? 'virage serré'
                  : gentle
                  ? 'courbe douce'
                  : 'virage'
            : tight
            ? '$side serrée'
            : gentle
            ? '$side douce'
            : side,
      _ =>
        side == null
            ? tight
                  ? 'sharp turn'
                  : gentle
                  ? 'gentle turn'
                  : 'turn'
            : medium
            ? side
            : '${tight
                  ? 'sharp'
                  : gentle
                  ? 'gentle'
                  : 'turn'} $side',
    };
  }

  String _rejoinSide(
    AppLanguage language,
    double? bearing,
    double? currentHeading,
  ) {
    if (bearing == null || currentHeading == null) {
      return _t(language, ko: '진행 방향', en: 'ahead', fr: 'devant');
    }
    final relative = (bearing - currentHeading) % 360;
    final normalized = relative < 0 ? relative + 360 : relative;
    if (normalized <= 20 || normalized >= 340) {
      return _t(language, ko: '정면', en: 'ahead', fr: 'devant');
    }
    final right = normalized < 180;
    return right
        ? _t(language, ko: '우측', en: 'right', fr: 'droite')
        : _t(language, ko: '좌측', en: 'left', fr: 'gauche');
  }

  String _pacedDistance(double meters) {
    if (meters >= 1000) return ((meters / 100).round() * 100).toString();
    return ((meters / 10).round() * 10).clamp(0, 990).toString();
  }

  // 재진입 가드는 쿨다운(5초)이 담당한다 — 별도 플래그는 두지 않는다
  Future<void> _speak(String phrase, AppLanguage language) async {
    _traceCandidatePhrase(phrase);
    try {
      final override = _speakOverride;
      if (override != null) {
        await override(phrase, language);
        return;
      }
      final speech = _speechQueue.then((_) async {
        if (_disposed) return;
        final tts = await _ensureTts(language);
        if (tts == null || _disposed) return;
        await tts.speak(phrase);
      });
      _speechQueue = speech.catchError((_) {});
      await speech;
    } catch (_) {
      // TTS 실패는 조용히 — 시각 배너가 항상 있다
    }
  }

  void _traceCandidatePhrase(String phrase) {
    if (!kDebugMode) return;
    _debugLog('[REVV][VoiceBriefing][candidate] $phrase');
  }

  Future<VoiceTtsClient?> _ensureTts(AppLanguage language) async {
    try {
      var tts = _tts;
      if (tts == null) {
        tts = _ttsFactory();
        await tts.configureAudioSession();
        await tts.setSpeechRate(
          defaultTargetPlatform == TargetPlatform.iOS ? 0.48 : 0.5,
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
    _disposed = true;
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

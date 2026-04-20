import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../models/revv_route.dart';
import 'jarvis_script.dart';

// ── 커브 강도 분류 ──────────────────────────────────────────────
enum CurveIntensity {
  gentle,   // 20~40°
  medium,   // 40~70°
  sharp,    // 70~110°
  hairpin,  // 110°+
}

extension CurveIntensityExt on CurveIntensity {
  String get label {
    switch (this) {
      case CurveIntensity.gentle:  return '완만';
      case CurveIntensity.medium:  return '중간';
      case CurveIntensity.sharp:   return '급커브';
      case CurveIntensity.hairpin: return '헤어핀';
    }
  }

  String get shortLabel {
    switch (this) {
      case CurveIntensity.gentle:  return 'GENTLE';
      case CurveIntensity.medium:  return 'MEDIUM';
      case CurveIntensity.sharp:   return 'SHARP';
      case CurveIntensity.hairpin: return 'HAIRPIN';
    }
  }

  // 방향(direction)과 합쳐 TTS 텍스트 생성
  String ttsText(String direction) {
    switch (this) {
      case CurveIntensity.gentle:
        return '완만한 $direction커브입니다';
      case CurveIntensity.medium:
        return '$direction커브 주의하세요';
      case CurveIntensity.sharp:
        return '급 $direction커브입니다, 속도 확인하세요';
      case CurveIntensity.hairpin:
        return '헤어핀 $direction커브입니다, 충분히 감속하세요';
    }
  }
}

// ── 코너 정보 ───────────────────────────────────────────────────
class CornerInfo {
  final double distanceM;      // 현재 위치에서 코너까지 거리 (m)
  final CurveIntensity intensity;
  final bool isRight;          // true = 우커브, false = 좌커브
  final double bearingDelta;   // 절댓값 방향 변화 (°)
  final int nodeIndex;         // 해당 노드 인덱스 (코너 정점)

  const CornerInfo({
    required this.distanceM,
    required this.intensity,
    required this.isRight,
    required this.bearingDelta,
    required this.nodeIndex,
  });

  String get directionKo => isRight ? '우' : '좌';

  bool get isSignificant => intensity == CurveIntensity.sharp || intensity == CurveIntensity.hairpin;
}

// ── 코너 브리핑 서비스 ──────────────────────────────────────────
/// 루트 진입 후 전방 노드를 분석하여 다음 코너를 감지, TTS로 미리 안내한다.
/// SprintScreen에서 _onRoute = true 상태일 때 updateLocation()을 호출한다.
class CornerBriefingService {
  // 탐색 범위
  static const double _lookAheadM  = 600.0; // 이 거리 이내 코너 탐색
  static const double _minAngle    = 20.0;  // 이 각도 이상만 코너로 인정
  static const double _announce1M  = 400.0; // 1차 예고 거리
  static const double _announce2M  = 120.0; // 2차 예고 거리

  final FlutterTts _tts = FlutterTts();
  bool _stopped = false;
  bool _muted   = false;
  bool get muted => _muted;

  // 현재 다음 코너
  CornerInfo? _nextCorner;
  CornerInfo? get nextCorner => _nextCorner;

  // 알림 상태 — 같은 코너에 중복 TTS 방지
  int _lastAnnouncedNode = -1;
  bool _announced1 = false;
  bool _announced2 = false;

  // 리스너 (UI 갱신용)
  VoidCallback? onUpdate;
  final void Function(String text)? onSpeak;
  final JarvisPersona persona;

  CornerBriefingService({
    this.onUpdate,
    this.onSpeak,
    this.persona = JarvisPersona.engineer,
    bool initialMuted = false,
  }) {
    _muted = initialMuted;
    _initTts();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('ko-KR');
    await _tts.setSpeechRate(0.88);
    await _tts.setVolume(1.0);
  }

  // ── 위치 업데이트 ──────────────────────────────────────────────
  /// [lat], [lng]: 현재 위치
  /// [nodes]: 전체 루트 노드
  /// [closestIdx]: 현재 위치에서 가장 가까운 노드 인덱스 (sprint_screen에서 계산됨)
  void updateLocation(double lat, double lng, List<LatLng> nodes, int closestIdx) {
    if (_stopped || nodes.isEmpty) return;

    // 전방 노드에서 다음 코너 탐색
    final corner = _findNextCorner(LatLng(lat, lng), nodes, closestIdx);
    final changed = corner?.nodeIndex != _nextCorner?.nodeIndex;
    _nextCorner = corner;

    if (corner == null) {
      if (changed) onUpdate?.call();
      return;
    }

    // 새로운 코너가 나타나면 알림 상태 초기화
    if (corner.nodeIndex != _lastAnnouncedNode) {
      _lastAnnouncedNode = corner.nodeIndex;
      _announced1 = false;
      _announced2 = false;
    }

    // 1차 예고 (~400m)
    if (!_announced1 && corner.distanceM <= _announce1M) {
      _announced1 = true;
      final distStr = '${corner.distanceM.round()}미터 앞';
      // gentle은 400m 예고 생략 (운전 흐름 방해)
      if (corner.intensity != CurveIntensity.gentle) {
        _speak('$distStr ${corner.intensity.ttsText(corner.directionKo)}');
      }
    }

    // 2차 예고 (~120m)
    if (!_announced2 && corner.distanceM <= _announce2M) {
      _announced2 = true;
      _speak(corner.intensity.ttsText(corner.directionKo));
    }

    if (changed) onUpdate?.call();
  }

  // ── 코너 탐색 알고리즘 ─────────────────────────────────────────
  /// closestIdx 이후 노드들을 순회하며 첫 번째 의미있는 코너를 반환
  CornerInfo? _findNextCorner(LatLng pos, List<LatLng> nodes, int closestIdx) {
    if (closestIdx + 2 >= nodes.length) return null;

    double cumDistM = _haversineM(pos, nodes[closestIdx]);

    for (int i = closestIdx + 1; i < nodes.length - 1; i++) {
      cumDistM += _haversineM(nodes[i - 1], nodes[i]);
      if (cumDistM > _lookAheadM) break;

      // 3점 (i-1, i, i+1) 으로 베어링 변화 계산
      final bIn  = _bearing(nodes[i - 1], nodes[i]);
      final bOut = _bearing(nodes[i], nodes[i + 1]);
      final delta = _normDelta(bOut - bIn); // -180 ~ +180

      final absDelta = delta.abs();
      if (absDelta < _minAngle) continue;

      // 강도 분류
      final intensity = _classify(absDelta);

      // gentle은 300m 이상이면 표시 생략 (노이즈)
      if (intensity == CurveIntensity.gentle && cumDistM > 300) continue;

      return CornerInfo(
        distanceM: cumDistM,
        intensity: intensity,
        isRight: delta > 0,
        bearingDelta: absDelta,
        nodeIndex: i,
      );
    }
    return null;
  }

  CurveIntensity _classify(double deg) {
    if (deg >= 110) return CurveIntensity.hairpin;
    if (deg >= 70)  return CurveIntensity.sharp;
    if (deg >= 40)  return CurveIntensity.medium;
    return CurveIntensity.gentle;
  }

  // ── 공개 API ────────────────────────────────────────────────────
  void toggleMute() {
    _muted = !_muted;
    if (_muted) _tts.stop();
    onUpdate?.call();
  }

  void reset() {
    _nextCorner = null;
    _lastAnnouncedNode = -1;
    _announced1 = false;
    _announced2 = false;
  }

  void stop() {
    _stopped = true;
    _tts.stop();
  }

  void _speak(String text) {
    if (_stopped || _muted) return;
    if (onSpeak != null) {
      onSpeak!(text);
      return;
    }
    _tts.speak(text);
  }

  // ── 수학 헬퍼 ────────────────────────────────────────────────────
  static double _haversineM(LatLng a, LatLng b) {
    const r = 6371000.0;
    final dLat = (b.lat - a.lat) * math.pi / 180;
    final dLng = (b.lng - a.lng) * math.pi / 180;
    final x = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(a.lat * math.pi / 180) *
            math.cos(b.lat * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(x), math.sqrt(1 - x));
  }

  /// 두 지점 사이의 방위각 (0~360°)
  static double _bearing(LatLng a, LatLng b) {
    final dLng = (b.lng - a.lng) * math.pi / 180;
    final lat1 = a.lat * math.pi / 180;
    final lat2 = b.lat * math.pi / 180;
    final y = math.sin(dLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  /// 베어링 차이 정규화 → -180 ~ +180 (양수=우, 음수=좌)
  static double _normDelta(double d) {
    while (d > 180) {
      d -= 360;
    }
    while (d < -180) {
      d += 360;
    }
    return d;
  }

  static ({int hairpin, int sharp, int medium, double firstCornerM}) analyzeFullRoute(
    LatLng userPos,
    List<LatLng> nodes,
  ) {
    if (nodes.length < 3) {
      return (hairpin: 0, sharp: 0, medium: 0, firstCornerM: 0.0);
    }

    int hairpin = 0;
    int sharp = 0;
    int medium = 0;
    double? firstCornerM;
    double distanceM = _haversineM(userPos, nodes.first);

    for (int i = 1; i < nodes.length - 1; i++) {
      distanceM += _haversineM(nodes[i - 1], nodes[i]);
      final delta = _normDelta(_bearing(nodes[i], nodes[i + 1]) - _bearing(nodes[i - 1], nodes[i])).abs();
      if (delta < 40) {
        continue;
      }
      firstCornerM ??= distanceM;
      if (delta >= 110) {
        hairpin++;
      } else if (delta >= 70) {
        sharp++;
      } else {
        medium++;
      }
    }

    return (
      hairpin: hairpin,
      sharp: sharp,
      medium: medium,
      firstCornerM: firstCornerM ?? 0.0,
    );
  }
}

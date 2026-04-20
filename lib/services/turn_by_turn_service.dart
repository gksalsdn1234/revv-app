import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../models/nav_step.dart';
import '../models/revv_route.dart';

class TurnByTurnService {
  final List<NavStep> steps;
  final VoidCallback onUpdate;

  int _idx = 0;
  bool _announced500 = false; // 급커브 사전 경고 (sharp turn만)
  bool _announced300 = false;
  bool _announced100 = false;
  bool _announcedStraight = false; // 직진 구간 진입 안내
  final FlutterTts _tts = FlutterTts();
  bool _stopped = false;
  bool _muted = false;

  int get currentIdx => _idx;
  bool get muted => _muted;

  /// 현재 보여줄 다음 스텝 (upcoming turn)
  NavStep? get upcomingStep =>
      _idx + 1 < steps.length ? steps[_idx + 1] : (_idx < steps.length ? steps[_idx] : null);

  /// 남은 스텝에 진짜 턴(좌/우/급커브/로터리 등)이 없으면 true
  bool get isStraightAhead {
    for (int i = _idx + 1; i < steps.length; i++) {
      final s = steps[i];
      if (s.type == 'arrive') continue;
      final m = s.modifier;
      if (m == 'left' || m == 'right' ||
          m == 'slight left' || m == 'slight right' ||
          m == 'sharp left' || m == 'sharp right' ||
          m == 'uturn') {
        return false;
      }
      if (s.type == 'roundabout' || s.type == 'rotary' ||
          s.type == 'fork' || s.type == 'end of road') {
        return false;
      }
    }
    return true;
  }

  TurnByTurnService({
    required this.steps,
    required this.onUpdate,
    bool initialMuted = false,
  }) {
    _muted = initialMuted;
    _initTts();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('ko-KR');
    await _tts.setSpeechRate(0.9);
    await _tts.setVolume(1.0);
    if (steps.isNotEmpty) await _tts.speak(steps[0].koreanInstruction);
  }

  /// modifier → 커브 강도 한국어
  String _curveWarning(NavStep step) {
    return switch (step.modifier) {
      'sharp left'   => '급좌회전 주의. ',
      'sharp right'  => '급우회전 주의. ',
      'left'         => '좌회전 커브. ',
      'right'        => '우회전 커브. ',
      'slight left'  => '완만한 좌측 커브. ',
      'slight right' => '완만한 우측 커브. ',
      _              => '',
    };
  }

  /// 위치 업데이트 — _onLocation에서 호출
  void updateLocation(double lat, double lng) {
    if (_stopped || _idx + 1 >= steps.length) return;

    final distM = _haversineM(LatLng(lat, lng), steps[_idx + 1].location);
    final next = steps[_idx + 1];

    // 500m 급커브 사전 경고 (sharp turn만)
    if (!_announced500 && distM < 500) {
      _announced500 = true;
      if (next.modifier == 'sharp left' || next.modifier == 'sharp right') {
        _speak('500미터 앞 ${_curveWarning(next)}속도를 줄이세요');
      }
    }

    // 300m 예고 — 커브 강도 포함
    if (!_announced300 && distM < 300) {
      _announced300 = true;
      final warning = _curveWarning(next);
      _speak('300미터 앞 $warning${next.koreanInstruction}');
    }

    // 80m 재안내
    if (!_announced100 && distM < 80) {
      _announced100 = true;
      _speak(next.koreanInstruction);
    }

    // 25m 이내 → 스텝 전진
    if (distM < 25) {
      _idx++;
      _announced500 = false;
      _announced300 = false;
      _announced100 = false;
      onUpdate();

      // 마지막 스텝(arrive) 도착
      if (_idx >= steps.length - 1) {
        _speak('목적지에 도착했습니다');
        return;
      }

      // 직진 구간 진입 — 남은 스텝에 턴 없을 때 1회만 안내
      if (!_announcedStraight && isStraightAhead) {
        _announcedStraight = true;
        _speak('앞으로 직진 구간입니다');
      }
    }
  }

  /// 다음 maneuver까지 거리(m)
  double distanceToNextM(double lat, double lng) {
    final targetIdx = _idx + 1 < steps.length ? _idx + 1 : _idx;
    return _haversineM(LatLng(lat, lng), steps[targetIdx].location);
  }

  void toggleMute() {
    _muted = !_muted;
    if (_muted) _tts.stop();
    onUpdate();
  }

  void _speak(String text) {
    if (!_stopped && !_muted) _tts.speak(text);
  }

  void stop() {
    _stopped = true;
    _tts.stop();
  }

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
}

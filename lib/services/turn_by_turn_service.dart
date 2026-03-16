import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../models/nav_step.dart';
import '../models/revv_route.dart';

class TurnByTurnService {
  final List<NavStep> steps;
  final VoidCallback onUpdate;

  int _idx = 0;
  bool _announced300 = false;
  bool _announced100 = false;
  final FlutterTts _tts = FlutterTts();
  bool _stopped = false;
  bool _muted = false;

  int get currentIdx => _idx;
  bool get muted => _muted;

  /// 현재 보여줄 다음 스텝 (upcoming turn)
  NavStep? get upcomingStep =>
      _idx + 1 < steps.length ? steps[_idx + 1] : (_idx < steps.length ? steps[_idx] : null);

  TurnByTurnService({required this.steps, required this.onUpdate}) {
    _initTts();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('ko-KR');
    await _tts.setSpeechRate(0.9);
    await _tts.setVolume(1.0);
    if (steps.isNotEmpty) await _tts.speak(steps[0].koreanInstruction);
  }

  /// 위치 업데이트 — _onLocation에서 호출
  void updateLocation(double lat, double lng) {
    if (_stopped || _idx + 1 >= steps.length) return;

    final distM = _haversineM(LatLng(lat, lng), steps[_idx + 1].location);

    // 300m 예고
    if (!_announced300 && distM < 300) {
      _announced300 = true;
      _speak('300미터 앞 ${steps[_idx + 1].koreanInstruction}');
    }

    // 80m 재안내
    if (!_announced100 && distM < 80) {
      _announced100 = true;
      _speak(steps[_idx + 1].koreanInstruction);
    }

    // 25m 이내 → 스텝 전진
    if (distM < 25) {
      _idx++;
      _announced300 = false;
      _announced100 = false;
      onUpdate();

      // 마지막 스텝(arrive) 도착
      if (_idx >= steps.length - 1) {
        _speak('목적지에 도착했습니다');
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

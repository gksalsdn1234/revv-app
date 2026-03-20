import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

enum DriveMode { cruise, winding, sport }

extension DriveModeExt on DriveMode {
  String get label {
    switch (this) {
      case DriveMode.cruise:
        return 'CRUISE';
      case DriveMode.winding:
        return 'WINDING';
      case DriveMode.sport:
        return 'SPORT';
    }
  }

  String get emoji {
    switch (this) {
      case DriveMode.cruise:
        return '🛣';
      case DriveMode.winding:
        return '🏔';
      case DriveMode.sport:
        return '⚡';
    }
  }

  Color get color {
    switch (this) {
      case DriveMode.cruise:
        return const Color(0xFF78909C); // gray
      case DriveMode.winding:
        return const Color(0xFF00BCD4); // teal
      case DriveMode.sport:
        return const Color(0xFFFFA726); // orange
    }
  }
}

class DrivingContextService extends ChangeNotifier {
  DriveMode _mode = DriveMode.cruise;
  double _windingIntensity = 0.0; // 0~1

  DriveMode get mode => _mode;
  double get windingIntensity => _windingIntensity;

  final List<double> _bearingHistory = [];
  static const _maxHistory = 12;

  // ChangeNotifierProxyProvider2.update()는 Flutter build 페이즈 도중 호출됨
  // → notifyListeners()를 build 도중 바로 호출하면 Consumer가 build 중 markNeedsBuild
  //   → 같은 build 패스에서 레이아웃 재시도 → !_debugDoingThisLayout assertion
  // _scheduleNotify()로 항상 프레임 완료 후 notify
  bool _notifyPending = false;
  void _scheduleNotify() {
    if (_notifyPending) return;
    _notifyPending = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _notifyPending = false;
      notifyListeners();
    });
  }

  // GPS 업데이트: bearing(heading)과 속도 전달
  void updateFromGPS(double? heading, double speedKmh) {
    if (heading == null || speedKmh < 8) {
      // 너무 느리면 bearing noise → 와인딩 계산 제외
      return;
    }

    _bearingHistory.add(heading);
    if (_bearingHistory.length > _maxHistory) {
      _bearingHistory.removeAt(0);
    }

    _computeWinding();
    _resolveMode();
    _scheduleNotify();
  }

  // OBD 업데이트: RPM과 속도로 스포츠 모드 추론
  void updateFromOBD(int? rpm, int? speedKmh) {
    if (rpm == null || speedKmh == null) return;

    // 30km/h 이상 주행 중 RPM/speed 비율이 높으면 스포츠 모드
    // rpm/speed > 100 이면 스포츠 (예: 3000rpm / 25kmh = 120)
    if (speedKmh >= 30 && rpm >= 3200) {
      final ratio = rpm / speedKmh;
      if (ratio > 90) {
        _setMode(DriveMode.sport);
        return;
      }
    }

    // 스포츠 조건 해제 → winding/cruise로 복귀
    if (_mode == DriveMode.sport) {
      _resolveMode();
      _scheduleNotify();
    }
  }

  void _computeWinding() {
    if (_bearingHistory.length < 2) {
      _windingIntensity = 0.0;
      return;
    }

    double totalDelta = 0;
    for (int i = 1; i < _bearingHistory.length; i++) {
      double delta = (_bearingHistory[i] - _bearingHistory[i - 1]).abs();
      if (delta > 180) delta = 360 - delta;
      totalDelta += delta;
    }

    final avgDelta = totalDelta / (_bearingHistory.length - 1);
    // 평균 20도/샘플 이상이면 매우 구불구불 → intensity = 1.0
    _windingIntensity = (avgDelta / 20.0).clamp(0.0, 1.0);
  }

  void _resolveMode() {
    if (_mode == DriveMode.sport) return; // OBD가 스포츠 설정하면 유지
    final newMode = _windingIntensity > 0.45 ? DriveMode.winding : DriveMode.cruise;
    _setMode(newMode);
  }

  void _setMode(DriveMode m) {
    if (_mode != m) {
      _mode = m;
      _scheduleNotify();
    }
  }

  void reset() {
    _bearingHistory.clear();
    _windingIntensity = 0.0;
    _mode = DriveMode.cruise;
    _scheduleNotify();
  }
}

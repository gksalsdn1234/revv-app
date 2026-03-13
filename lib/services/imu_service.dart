import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum MountType {
  dashFlat,   // 대시보드 수평 (화면 위)
  ventPort,   // 에어컨 마운트 세로 (화면 앞)
  ventLand,   // 에어컨 마운트 가로 (화면 앞)
  windshield, // 앞유리 마운트 세로
}

class ImuService extends ChangeNotifier {
  static const double _g = 9.81;

  MountType _mountType = MountType.dashFlat;
  MountType get mountType => _mountType;

  // 캘리브레이션 오프셋 (정지 상태에서 측정한 기준값)
  double _offX = 0, _offY = 0, _offZ = 0;
  bool _calibrated = false;
  bool get calibrated => _calibrated;

  // 현재 원시 가속도계 값 (m/s²)
  double _rawX = 0, _rawY = 0, _rawZ = -_g;

  // 현재 자이로스코프 값 (rad/s)
  double _gyrY = 0, _gyrZ = 0;

  // 세션 최대 G값
  double _maxLateralG = 0;
  double _maxLonG = 0;
  double get maxLateralG => _maxLateralG;
  double get maxLonG => _maxLonG;

  void resetMaxG() {
    _maxLateralG = 0;
    _maxLonG = 0;
    notifyListeners();
  }

  StreamSubscription? _accelSub;
  StreamSubscription? _gyroSub;

  // ── 공개 G값 ──────────────────────────────────────────────

  /// 횡가속도 (좌: -, 우: +) in G
  double get lateralG => _lateral() / _g;

  /// 종가속도 (감속: -, 가속: +) in G
  double get longitudinalG => _longitudinal() / _g;

  /// 요레이트 (좌: -, 우: +) in °/s
  double get yawRateDps => _yaw() * 180 / math.pi;

  /// 현재 원시값 (캘리브레이션 UI용)
  double get rawLateral => _lateral();
  double get rawLongitudinal => _longitudinal();

  // ── 마운트 타입별 축 매핑 ──────────────────────────────────

  double _lateral() {
    switch (_mountType) {
      case MountType.dashFlat:   return _rawX - _offX;
      case MountType.ventPort:   return _rawX - _offX;
      case MountType.ventLand:   return _rawY - _offY;
      case MountType.windshield: return _rawX - _offX;
    }
  }

  double _longitudinal() {
    switch (_mountType) {
      case MountType.dashFlat:   return _rawY - _offY;
      case MountType.ventPort:   return -(_rawZ - _offZ);
      case MountType.ventLand:   return -(_rawZ - _offZ);
      case MountType.windshield: return -(_rawZ - _offZ);
    }
  }

  double _yaw() {
    switch (_mountType) {
      case MountType.dashFlat:   return _gyrZ;
      case MountType.ventPort:   return _gyrY;
      case MountType.ventLand:   return _gyrY;
      case MountType.windshield: return _gyrY;
    }
  }

  // ── 초기화 ────────────────────────────────────────────────

  ImuService() {
    _loadPrefs().then((_) => _startSensors());
  }

  void _startSensors() {
    _accelSub = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 20), // 50Hz
    ).listen((e) {
      _rawX = e.x;
      _rawY = e.y;
      _rawZ = e.z;
      final lG = (_lateral() / _g).abs();
      final nG = (_longitudinal() / _g).abs();
      if (lG > _maxLateralG) _maxLateralG = lG;
      if (nG > _maxLonG) _maxLonG = nG;
      notifyListeners();
    });

    _gyroSub = gyroscopeEventStream(
      samplingPeriod: const Duration(milliseconds: 20),
    ).listen((e) {
      _gyrY = e.y;
      _gyrZ = e.z;
    });
  }

  // ── Public API ────────────────────────────────────────────

  void setMountType(MountType type) {
    _mountType = type;
    _calibrated = false;
    _offX = _offY = _offZ = 0;
    _savePrefs();
    notifyListeners();
  }

  /// 차량 정지 상태에서 호출 — 현재 값을 기준점으로 저장
  void calibrate() {
    _offX = _rawX;
    _offY = _rawY;
    _offZ = _rawZ;
    _calibrated = true;
    _savePrefs();
    notifyListeners();
  }

  void resetCalibration() {
    _offX = _offY = _offZ = 0;
    _calibrated = false;
    _savePrefs();
    notifyListeners();
  }

  // ── SharedPreferences ──────────────────────────────────────

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    final idx = p.getInt('imu_mount') ?? 0;
    _mountType = MountType.values[idx.clamp(0, MountType.values.length - 1)];
    _offX = p.getDouble('imu_ox') ?? 0;
    _offY = p.getDouble('imu_oy') ?? 0;
    _offZ = p.getDouble('imu_oz') ?? 0;
    _calibrated = p.getBool('imu_cal') ?? false;
  }

  Future<void> _savePrefs() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('imu_mount', _mountType.index);
    await p.setDouble('imu_ox', _offX);
    await p.setDouble('imu_oy', _offY);
    await p.setDouble('imu_oz', _offZ);
    await p.setBool('imu_cal', _calibrated);
  }

  @override
  void dispose() {
    _accelSub?.cancel();
    _gyroSub?.cancel();
    super.dispose();
  }
}

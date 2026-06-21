import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum MountType {
  dashFlat, // 대시보드 수평 (화면 위)
  ventPort, // 에어컨 마운트 세로 (화면 앞)
  ventLand, // 에어컨 마운트 가로 (화면 앞)
  windshield, // 앞유리 마운트 세로
}

class ImuService extends ChangeNotifier {
  static const double _g = 9.81;
  static const Duration _driveSamplingPeriod = Duration(milliseconds: 50);

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
  bool _notifyPending = false; // 프레임당 1회만 notify (레이아웃 assertion 방지)
  int _sensorClients = 0;
  Future<void>? _startingSensors;
  late final Future<void> _prefsReady;

  bool get isActive =>
      _accelSub != null || _gyroSub != null || _startingSensors != null;

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
      case MountType.dashFlat:
        return _rawX - _offX;
      case MountType.ventPort:
        return _rawX - _offX;
      case MountType.ventLand:
        return _rawY - _offY;
      case MountType.windshield:
        return _rawX - _offX;
    }
  }

  double _longitudinal() {
    switch (_mountType) {
      case MountType.dashFlat:
        return _rawY - _offY;
      case MountType.ventPort:
        return -(_rawZ - _offZ);
      case MountType.ventLand:
        return -(_rawZ - _offZ);
      case MountType.windshield:
        return -(_rawZ - _offZ);
    }
  }

  double _yaw() {
    switch (_mountType) {
      case MountType.dashFlat:
        return _gyrZ;
      case MountType.ventPort:
        return _gyrY;
      case MountType.ventLand:
        return _gyrY;
      case MountType.windshield:
        return _gyrY;
    }
  }

  // ── 초기화 ────────────────────────────────────────────────

  ImuService() {
    _prefsReady = _loadPrefs();
  }

  Future<void> start() {
    _sensorClients++;
    _startingSensors ??= _startSensors().whenComplete(() {
      _startingSensors = null;
    });
    return _startingSensors!;
  }

  void stop() {
    if (_sensorClients > 0) _sensorClients--;
    if (_sensorClients > 0) return;

    final wasActive = isActive;
    unawaited(_accelSub?.cancel());
    unawaited(_gyroSub?.cancel());
    _accelSub = null;
    _gyroSub = null;
    _notifyPending = false;
    if (wasActive) notifyListeners();
  }

  Future<void> _startSensors() async {
    if (_accelSub != null || _gyroSub != null) return;
    await _prefsReady;
    if (_sensorClients <= 0) return;

    _accelSub =
        accelerometerEventStream(
          samplingPeriod: _driveSamplingPeriod, // 20Hz, 주행 중에만 활성화
        ).listen((e) {
          _rawX = e.x;
          _rawY = e.y;
          _rawZ = e.z;
          final lG = (_lateral() / _g).abs();
          final nG = (_longitudinal() / _g).abs();
          if (lG > _maxLateralG) _maxLateralG = lG;
          if (nG > _maxLonG) _maxLonG = nG;
          // addPostFrameCallback으로 감싸야 layout 패스 중 notifyListeners() 호출 방지
          // → '!_debugDoingThisLayout' assertion + RenderBox not laid out 해결
          // 프레임당 1회만 등록 (50Hz 센서가 한 프레임 안에 여러 번 올 수 있음)
          if (!_notifyPending) {
            _notifyPending = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _notifyPending = false;
              notifyListeners();
            });
          }
        });

    _gyroSub = gyroscopeEventStream(samplingPeriod: _driveSamplingPeriod)
        .listen((e) {
          _gyrY = e.y;
          _gyrZ = e.z;
        });

    notifyListeners();
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
    _sensorClients = 0;
    unawaited(_accelSub?.cancel());
    unawaited(_gyroSub?.cancel());
    _accelSub = null;
    _gyroSub = null;
    super.dispose();
  }
}
